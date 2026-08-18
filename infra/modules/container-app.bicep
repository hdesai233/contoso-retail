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

@description('Name of the existing ACR (not the login server URL) — used to grant this service\'s identity AcrPull. Every service pulling from the same registry needs this grant; without it, image pulls fail.')
param acrName string

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

@description('Revision suffix, appended to the auto-incrementing revision name. Pass something unique per deploy (a timestamp, a commit SHA) — without it, an ARM-level redeploy of an existing Container App does not reliably roll a new revision even when template properties like env vars change, so the old replica keeps running unchanged. Discovered the hard way: env var updates silently did not restart the container until this was added.')
param revisionSuffix string = utcNow('yyyyMMddHHmmss')

var containerAppName = 'ca-${serviceName}-${env}'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
// managedIdentityId is a full resource ID; extract the identity name to
// declare an `existing` reference (Bicep can't resolve .properties.principalId
// from an ID string alone — it needs a typed resource reference).
var managedIdentityName = last(split(managedIdentityId, '/'))

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: managedIdentityName
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, managedIdentityId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

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
      revisionSuffix: revisionSuffix
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
  // Wait for the AcrPull grant before the platform attempts its first image
  // pull — RBAC propagation isn't instant, and pulling before the role
  // assignment lands would fail.
  dependsOn: [acrPullRoleAssignment]
}

output containerAppId string = containerApp.id
output containerAppName string = containerApp.name
output fqdn string = enableIngress ? containerApp.properties.configuration.ingress.fqdn : ''
