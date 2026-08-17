// main.bicep — entry point for the Contoso Retail infrastructure.
// See docs/02-Architecture.md and docs/03-Implementation-Guide.md.

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------

@description('Short workload name used in resource names')
param workload string = 'contoso'

@allowed(['dev', 'test', 'prod'])
@description('Environment')
param env string

@description('Region for all resources')
param location string = resourceGroup().location

@description('CAF region abbreviation used in resource names — must match `location`. Not derived automatically since Bicep has no location-to-abbreviation mapping. See docs/naming.md and docs/decisions/ADR-001-dev-region-eastus.md; dev uses eus (eastus), test/prod use eus2 (eastus2) pending confirmation their subscriptions allow it.')
param regionAbbr string = 'eus2'

// -----------------------------------------------------------------------------
// Common tags applied to every resource
// -----------------------------------------------------------------------------

var tags = {
  workload: workload
  env: env
  managedBy: 'bicep'
}

// Resource names computed here (rather than inside their module) because
// they're needed as inputs by other modules, e.g. keyVaultName feeds
// keyvault.bicep, which also needs subnetId/privateDnsZoneId from network.bicep.
var keyVaultName = 'kv-${workload}-${env}-${regionAbbr}-01'

// -----------------------------------------------------------------------------
// Modules — uncomment and wire up as each phase is completed.
// Order matters: observability → network → keyvault → identity → data → compute → ai → analytics → edge
// -----------------------------------------------------------------------------

// Phase 1
// module observability 'modules/observability.bicep' = { name: 'observability', params: { workload: workload, env: env, location: location, regionAbbr: regionAbbr, tags: tags } }
// module network       'modules/network.bicep'       = { name: 'network',       params: { workload: workload, env: env, location: location, regionAbbr: regionAbbr, tags: tags } }
// module keyvault      'modules/keyvault.bicep'      = { name: 'keyvault',      params: { keyVaultName: keyVaultName, location: location, tags: tags, subnetId: network.outputs.privateEndpointSubnetId, privateDnsZoneId: network.outputs.keyVaultPrivateDnsZoneId, laWorkspaceId: observability.outputs.laWorkspaceId } }
// module identity      'modules/identity.bicep'      = { name: 'identity',      params: { env: env, location: location, tags: tags } }
// // defender.bicep is subscription-scoped and subscription-wide — deploy once total, not once per environment. Needs `scope: subscription()` since main.bicep itself is resourceGroup-scoped.
// module defender      'modules/defender.bicep'      = { name: 'defender', scope: subscription(), params: {} }

// Phase 2
// module acr              'modules/acr.bicep'              = { name: 'acr', params: { workload: workload, env: env, location: location, regionAbbr: regionAbbr, tags: tags, subnetId: network.outputs.privateEndpointSubnetId, privateDnsZoneId: network.outputs.acrPrivateDnsZoneId, laWorkspaceId: observability.outputs.laWorkspaceId, keyVaultName: keyVaultName } }
// // aks.bicep is unused — kept per ADR-002 (subscription vCPU quota wall). Phase 2 compute is container-apps-env.bicep + container-app.bicep instead.
// module containerAppsEnv 'modules/container-apps-env.bicep' = { name: 'containerAppsEnv', params: { workload: workload, env: env, location: location, regionAbbr: regionAbbr, tags: tags, acaSubnetId: network.outputs.acaSubnetId, laWorkspaceName: observability.outputs.laWorkspaceName } }
// // Per-service Container Apps get wired here as each microservice is built, e.g.:
// // module catalogSvc 'modules/container-app.bicep' = { name: 'catalogSvc', params: { serviceName: 'catalog-svc', env: env, location: location, tags: tags, containerAppsEnvironmentId: containerAppsEnv.outputs.containerAppsEnvId, image: '${acr.outputs.acrLoginServer}/catalog-svc:0.1.0', acrLoginServer: acr.outputs.acrLoginServer, managedIdentityId: filter(identity.outputs.managedIdentities, i => i.service == 'catalog-svc')[0].id } }

// Phase 3
// module cosmos        'modules/cosmos.bicep'        = { ... }
// module sql           'modules/sql.bicep'           = { ... }
// module storage       'modules/storage.bicep'       = { ... }
// module redis         'modules/redis.bicep'         = { ... }
// module serviceBus    'modules/service-bus.bicep'   = { ... }

// Phase 4
// module openai        'modules/openai.bicep'        = { ... }
// module aiSearch      'modules/ai-search.bicep'     = { ... }
// module aiServices    'modules/ai-services.bicep'   = { ... }

// Phase 5
// module eventhubs        'modules/eventhubs.bicep'        = { ... }
// module storageAdls      'modules/storage-adls.bicep'     = { ... }
// module streamAnalytics  'modules/stream-analytics.bicep' = { ... }
// module synapse          'modules/synapse.bicep'          = { ... }
// module purview          'modules/purview.bicep'          = { ... }

// Phase 6
// module apim          'modules/apim.bicep'          = { ... }
// module frontDoor     'modules/front-door.bicep'    = { ... }

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------

output workloadName string = workload
output environment  string = env
output location     string = location
