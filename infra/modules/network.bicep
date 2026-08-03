// network.bicep — Phase 1
// VNet with baseline subnets and per-subnet NSGs for AKS, Application Gateway,
// Private Endpoints, and APIM.
//
// Jumpbox and AzureBastionSubnet are documented in docs/naming.md but not
// added here yet — TODO: add once the jumpbox access pattern is decided.
//
// See docs/03-Implementation-Guide.md Phase 1 and docs/naming.md for the
// naming and addressing this module follows.

targetScope = 'resourceGroup'

@minLength(1)
@description('Short workload name, e.g. contoso')
param workload string

@allowed(['dev', 'test', 'prod'])
@description('Environment')
param env string

@description('Location for the resource(s)')
param location string = resourceGroup().location

@description('CAF region abbreviation used in resource names. Bicep has no built-in location-to-abbreviation mapping, so this must be kept in sync with `location` and docs/naming.md.')
param regionAbbr string = 'eus2'

@description('Tags applied to all resources')
param tags object = {}

@description('Address space for the VNet')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Address prefix for the AKS system node pool subnet')
param systemPoolSubnetPrefix string = '10.20.0.0/22'

@description('Address prefix for the AKS user node pool subnet')
param userPoolSubnetPrefix string = '10.20.4.0/22'

@description('Address prefix for the Application Gateway subnet')
param appGwSubnetPrefix string = '10.20.8.0/24'

@description('Address prefix for the Private Endpoints subnet')
param peSubnetPrefix string = '10.20.9.0/24'

@description('Address prefix for the APIM subnet')
param apimSubnetPrefix string = '10.20.10.0/24'

var vnetName = 'vnet-${workload}-${env}-${regionAbbr}'

// -----------------------------------------------------------------------------
// NSGs — one per subnet. Only the inbound rules Azure requires for a subnet's
// dedicated resource type are added; everything else relies on the NSG
// default rules (deny internet inbound, allow VNet + Azure Load Balancer).
// -----------------------------------------------------------------------------

resource nsgSystemPool 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-aks-systempool-${env}-${regionAbbr}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource nsgUserPool 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-aks-userpool-${env}-${regionAbbr}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource nsgAppGw 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-appgw-${env}-${regionAbbr}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        // Mandatory for the v2 SKU's backend health probes, independent of
        // any app traffic rules — deployment fails without it.
        // https://learn.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '65200-65535'
        }
      }
    ]
  }
}

resource nsgPe 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-pe-${env}-${regionAbbr}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource nsgApim 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-apim-${env}-${regionAbbr}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        // Control-plane management endpoint; required in both External and
        // Internal VNet integration modes.
        // https://learn.microsoft.com/azure/api-management/api-management-using-with-vnet#nsg-rules
        name: 'AllowApiManagementInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// VNet + subnets
// -----------------------------------------------------------------------------

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'snet-aks-systempool'
        properties: {
          addressPrefix: systemPoolSubnetPrefix
          networkSecurityGroup: { id: nsgSystemPool.id }
        }
      }
      {
        name: 'snet-aks-userpool'
        properties: {
          addressPrefix: userPoolSubnetPrefix
          networkSecurityGroup: { id: nsgUserPool.id }
        }
      }
      {
        name: 'snet-appgw'
        properties: {
          addressPrefix: appGwSubnetPrefix
          networkSecurityGroup: { id: nsgAppGw.id }
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: peSubnetPrefix
          networkSecurityGroup: { id: nsgPe.id }
          // Required for Azure Private Endpoints to be created in this subnet.
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-apim'
        properties: {
          addressPrefix: apimSubnetPrefix
          networkSecurityGroup: { id: nsgApim.id }
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Private DNS zones — one per data-service type that needs Private Endpoint
// name resolution, linked to this VNet. Only Key Vault's zone exists so far;
// add more here as their modules (Cosmos, SQL, Storage, Redis, ...) land.
// -----------------------------------------------------------------------------

resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource keyVaultPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

output vnetId string = vnet.id
output vnetName string = vnet.name
output systemPoolSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-aks-systempool')
output userPoolSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-aks-userpool')
output appGwSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-appgw')
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-pe')
output apimSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-apim')
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.id
