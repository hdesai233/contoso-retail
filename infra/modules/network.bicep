// network.bicep — Phase 1
// VNet with baseline subnets and per-subnet NSGs for Container Apps,
// Application Gateway, Private Endpoints, and APIM.
//
// snet-aca replaced snet-aks-systempool/snet-aks-userpool per ADR-002 (AKS
// pivoted to Azure Container Apps after a subscription vCPU quota wall).
// It's deliberately NOT delegated and sized /23 — Consumption-only Container
// Apps environments require exactly that, the opposite of what a delegated
// AKS-style subnet would need.
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

@description('Address prefix for the Container Apps subnet. Must be >= /23 and must NOT be delegated — Consumption-only environment requirement.')
param acaSubnetPrefix string = '10.20.16.0/23'

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

resource nsgAca 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-aca-${env}-${regionAbbr}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        // Client HTTP/HTTPS access to the environment's external ingress.
        // https://learn.microsoft.com/azure/container-apps/firewall-integration
        name: 'AllowClientHttpHttpsInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: ['80', '443']
        }
      }
      {
        // Azure Load Balancer probing backend pools in a Consumption-only
        // environment — the dynamic port range Container Apps requires.
        name: 'AllowLoadBalancerProbeInbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '30000-32767'
        }
      }
    ]
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
        name: 'snet-aca'
        properties: {
          addressPrefix: acaSubnetPrefix
          networkSecurityGroup: { id: nsgAca.id }
          // Consumption-only Container Apps environments must NOT be
          // delegated to Microsoft.App/environments — that delegation is
          // only for Workload profile environments, which use dedicated
          // VM-backed compute and would hit the same vCPU quota wall AKS
          // did. Deliberately no `delegations` property here.
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
// name resolution, linked to this VNet. Added incrementally, one per module,
// as each lands (Key Vault in Phase 1, ACR in Phase 2) — see
// docs/03-Implementation-Guide.md Phase 1 step 2 for why. Add more here as
// Cosmos, SQL, Storage, AI Search, OpenAI, etc. land in later phases.
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

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
  tags: tags
}

resource acrPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrPrivateDnsZone
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
output acaSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-aca')
output appGwSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-appgw')
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-pe')
output apimSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-apim')
output keyVaultPrivateDnsZoneId string = keyVaultPrivateDnsZone.id
output acrPrivateDnsZoneId string = acrPrivateDnsZone.id
