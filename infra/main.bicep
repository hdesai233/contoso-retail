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

// -----------------------------------------------------------------------------
// Common tags applied to every resource
// -----------------------------------------------------------------------------

var tags = {
  workload: workload
  env: env
  managedBy: 'bicep'
}

// -----------------------------------------------------------------------------
// Modules — uncomment and wire up as each phase is completed.
// Order matters: observability → network → keyvault → identity → data → compute → ai → analytics → edge
// -----------------------------------------------------------------------------

// Phase 1
// module observability 'modules/observability.bicep' = { name: 'observability', params: { workload: workload, env: env, location: location, tags: tags } }
// module network       'modules/network.bicep'       = { name: 'network',       params: { workload: workload, env: env, location: location, tags: tags } }
// module keyvault      'modules/keyvault.bicep'      = { name: 'keyvault',      params: { workload: workload, env: env, location: location, tags: tags, subnetId: network.outputs.privateEndpointSubnetId, laWorkspaceId: observability.outputs.laWorkspaceId } }
// module identity      'modules/identity.bicep'      = { name: 'identity',      params: { workload: workload, env: env, location: location, tags: tags } }
// module defender      'modules/defender.bicep'      = { name: 'defender',      params: { workload: workload, env: env } }

// Phase 2
// module acr           'modules/acr.bicep'           = { name: 'acr', ... }
// module aks           'modules/aks.bicep'           = { name: 'aks', ... }

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
