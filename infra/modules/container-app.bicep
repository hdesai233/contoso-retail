// container-app.bicep — Phase 2
// Reusable per-service Container App module (mirrors the loop pattern in
// identity.bicep — one invocation per microservice). Pulls from ACR via the
// service's own Managed Identity, never admin credentials. No Kubernetes
// concepts (ServiceAccount, Deployment, Kustomize) — see ADR-002.
//
// See docs/03-Implementation-Guide.md Phase 2 and docs/naming.md.

targetScope = 'resourceGroup'

@minLength(1)
@description('Service name, e.g. catalog-svc — matches the {service} token in mi-{service}-{env} from identity.bicep')
param serviceName string

@allowed(['dev', 'test', 'prod'])
@description('Environment')
param env string

@description('Location for the resource(s)')
param location string = resourceGroup().location

@description('Tags applied to all resources')
param tags object = {}

@description('Resource ID of the Container Apps Managed Environment (container-apps-env.bicep)')
param containerAppsEnvironmentId string

@description('Full image reference, e.g. acrcontosodeveus.azurecr.io/catalog-svc:0.1.0')
param image string

@description('ACR login server, e.g. acrcontosodeveus.azurecr.io — used for registry auth, kept separate from `image` so this module does not need to parse it out')
param acrLoginServer string

@description('Resource ID of this service\'s existing User-Assigned Managed Identity (from identity.bicep). Used for both ACR pull and any Azure SDK calls the app makes with DefaultAzureCredential.')
param managedIdentityId string

@description('Whether this app has an ingress endpoint at all. False for background workers like moderation-worker.')
param enableIngress bool = true

@description('Whether ingress is reachable from the public internet vs only from inside the Container Apps environment. Ignored if enableIngress is false.')
param externalIngress bool = true

@description('Port the container listens on. Ignored if enableIngress is false.')
param targetPort int = 8080

@description('CPU cores for the container, e.g. 0.25, 0.5, 1')
param cpu string = '0.25'

@description('Memory for the container, e.g. 0.5Gi, 1Gi — must be a valid cpu/memory combination per Container Apps limits')
param memoryValue string = '0.5Gi'

@description('Minimum replica count. 0 allows scale-to-zero for infrequently-used services.')
param minReplicas int = 1

@description('Maximum replica count')
param maxReplicas int = 3

@description('KEDA scale rules, e.g. an azureQueue rule for a Service Bus-triggered worker. Empty array uses Consumption\'s default HTTP-concurrency scaling, which is sufficient for a typical web API.')
param scaleRules array = []

@description('Non-secret environment variables, e.g. Cosmos endpoint URL. Never put secrets here — read them from Key Vault via DefaultAzureCredential in app code instead.')
param envVars array = []

var containerAppName = 'ca-${serviceName}-${env}'

resource containerApp 'Microsoft.App/containerApps@2026-01-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: enableIngress ? {
        external: externalIngress
        targetPort: targetPort
      } : null
      registries: [
        {
          server: acrLoginServer
          identity: managedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: serviceName
          image: image
          resources: {
            cpu: json(cpu)
            memory: memoryValue
          }
          env: envVars
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: scaleRules
      }
    }
  }
}

output containerAppId string = containerApp.id
output containerAppName string = containerApp.name
output fqdn string = enableIngress ? containerApp.properties.configuration.ingress.fqdn : ''
