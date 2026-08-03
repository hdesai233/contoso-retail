// keyvault.bicep — Phase 1
// Key Vault (Premium) with RBAC auth, soft-delete + purge protection, no
// public network access, a Private Endpoint in snet-pe, and diagnostic
// settings (AuditEvent, AllMetrics) to the shared Log Analytics workspace.
//
// See docs/03-Implementation-Guide.md Phase 1 and docs/naming.md.

targetScope = 'resourceGroup'

@minLength(3)
@maxLength(24)
@description('Key Vault name. Caller is responsible for the CAF name (kv-{workload}-{env}-{region}[-nn]) and the 24-char limit — see docs/naming.md.')
param keyVaultName string

@description('Location for the resource(s)')
param location string = resourceGroup().location

@description('Tags applied to all resources')
param tags object = {}

@description('Subnet ID (snet-pe) the Private Endpoint is deployed into')
param subnetId string

@description('Private DNS zone ID for privatelink.vaultcore.azure.net, linked to the VNet')
param privateDnsZoneId string

@description('Log Analytics workspace resource ID that AuditEvent logs and AllMetrics are sent to')
param laWorkspaceId string

@description('Public network access. Defaults to disabled per CLAUDE.md house rule 2; the dev overlay may explicitly override to true for convenience.')
param publicNetworkAccessEnabled bool = false

@minValue(7)
@maxValue(90)
@description('Soft-delete retention in days. Immutable after the vault is created — changing it later requires a new vault.')
param softDeleteRetentionInDays int = 90

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'premium'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    // Soft-delete cannot be disabled on current API versions; kept explicit
    // for readability.
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: true
    publicNetworkAccess: publicNetworkAccessEnabled ? 'Enabled' : 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pep-${keyVaultName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${keyVaultName}-plsc'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
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
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${keyVaultName}'
  scope: keyVault
  properties: {
    workspaceId: laWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
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

output vaultUri string = keyVault.properties.vaultUri
