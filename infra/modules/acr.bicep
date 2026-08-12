// acr.bicep — Phase 2
// Azure Container Registry (Premium), Private Endpoint in snet-pe, customer-
// managed key from Key Vault, diagnostic settings to LA. Admin user disabled —
// pulls/pushes authenticate via Managed Identity (kubelet identity for AKS,
// caller's AAD identity for `az acr build`), never a shared key.
//
// Vulnerability scanning on push is NOT configured here. ACR's own legacy
// "quarantine policy" is deprecated; the current recommended path is the
// Containers plan on Microsoft Defender for Cloud, which is Phase 6 in this
// guide (defender.bicep gets extended there). The Phase 2 exit criterion
// "image scan on push reports no Critical/High CVEs" won't be checkable
// until that plan is enabled.
//
// See docs/03-Implementation-Guide.md Phase 2 and docs/naming.md.

targetScope = 'resourceGroup'

@minLength(1)
@description('Short workload name, e.g. contoso')
param workload string

@allowed(['dev', 'test', 'prod'])
@description('Environment')
param env string

@description('Location for the resource(s)')
param location string = resourceGroup().location

@description('CAF region abbreviation used in resource names. Must match `location` — see docs/naming.md.')
param regionAbbr string = 'eus2'

@description('Tags applied to all resources')
param tags object = {}

@description('Subnet ID (snet-pe) the Private Endpoint is deployed into')
param subnetId string

@description('Private DNS zone ID for privatelink.azurecr.io, linked to the VNet — see network.bicep')
param privateDnsZoneId string

@description('Log Analytics workspace resource ID that registry events and metrics are sent to')
param laWorkspaceId string

@description('Public network access. Defaults to disabled per CLAUDE.md house rule 2; the dev overlay may explicitly override to true for convenience.')
param publicNetworkAccessEnabled bool = false

@description('Enable customer-managed key encryption. Adds a dedicated User-Assigned Identity, a Key Vault RSA key, and a role assignment — real complexity for a learning project. Defaults to true per the Phase 2 spec; set false to skip all of it and use Microsoft-managed keys instead.')
param enableCustomerManagedKey bool = true

@description('Name of the existing Key Vault to source the customer-managed key from. Required when enableCustomerManagedKey is true.')
param keyVaultName string = ''

var acrName = toLower('acr${workload}${env}${regionAbbr}')

// -----------------------------------------------------------------------------
// Customer-managed key. Uses a dedicated User-Assigned Identity rather than
// ACR's system-assigned one: CMK setup needs the identity to already have Key
// Vault access before the registry is created with encryption enabled, but a
// system-assigned identity's principal ID doesn't exist until the registry
// itself is created — a circular dependency. A pre-created UAMI breaks that
// cycle. https://learn.microsoft.com/azure/container-registry/tutorial-enable-customer-managed-keys
// -----------------------------------------------------------------------------

resource cmkIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (enableCustomerManagedKey) {
  name: 'mi-acr-cmk-${env}'
  location: location
  tags: tags
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (enableCustomerManagedKey) {
  name: keyVaultName
}

resource cmkKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = if (enableCustomerManagedKey) {
  parent: keyVault
  name: 'acr-cmk'
  properties: {
    kty: 'RSA'
    keySize: 2048
  }
}

// Built-in "Key Vault Crypto Service Encryption User" role — lets the
// identity wrap/unwrap the key without any broader Key Vault access.
var cryptoServiceEncryptionUserRoleId = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

resource cmkRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableCustomerManagedKey) {
  // Non-null assertions (!) below are safe: this resource and cmkIdentity/
  // keyVault share the same enableCustomerManagedKey condition, so if this
  // resource is being deployed, they exist too. Bicep's type checker can't
  // infer that two independently-conditioned resources share a condition.
  name: guid(keyVault!.id, cmkIdentity!.id, cryptoServiceEncryptionUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cryptoServiceEncryptionUserRoleId)
    principalId: cmkIdentity!.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// -----------------------------------------------------------------------------
// Registry
// -----------------------------------------------------------------------------

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
  }
  identity: enableCustomerManagedKey ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${cmkIdentity!.id}': {}
    }
  } : {
    type: 'None'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: publicNetworkAccessEnabled ? 'Enabled' : 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    // Paired with publicNetworkAccess: disabling export alongside public
    // access is Microsoft's recommended combination for full network
    // isolation — otherwise content can still leave via cross-registry
    // export even with public access off.
    policies: {
      exportPolicy: {
        status: publicNetworkAccessEnabled ? 'enabled' : 'disabled'
      }
    }
    encryption: enableCustomerManagedKey ? {
      status: 'enabled'
      keyVaultProperties: {
        identity: cmkIdentity!.properties.clientId
        keyIdentifier: cmkKey!.properties.keyUriWithVersion
      }
    } : {
      status: 'disabled'
    }
  }
  dependsOn: enableCustomerManagedKey ? [cmkRoleAssignment] : []
}

// -----------------------------------------------------------------------------
// Private Endpoint
// -----------------------------------------------------------------------------

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pep-${acrName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${acrName}-plsc'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: ['registry']
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${acrName}'
  scope: acr
  properties: {
    workspaceId: laWorkspaceId
    logs: [
      {
        category: 'ContainerRegistryRepositoryEvents'
        enabled: true
      }
      {
        category: 'ContainerRegistryLoginEvents'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output acrId string = acr.id
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
