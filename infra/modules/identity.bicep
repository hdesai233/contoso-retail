// identity.bicep — Phase 1
// User-Assigned Managed Identities for the eight microservices (placeholders
// for now, per docs/03-Implementation-Guide.md Phase 1).
//
// Role assignments are deliberately NOT created here: every target resource
// they'd scope to (Cosmos containers, Service Bus queues, Storage
// containers, ...) is a later phase and doesn't exist yet. Add role
// assignments alongside each resource's own module once it's implemented —
// e.g. the Cosmos "Built-in Data Contributor" assignment for review-svc
// belongs in cosmos.bicep, not here, so it lives next to the resource it
// grants access to.
//
// Federated credentials (binding each identity to an AKS ServiceAccount) are
// also out of scope here — they need the AKS OIDC issuer URL, which doesn't
// exist until aks.bicep (Phase 2) is deployed. See docs/03-Implementation-Guide.md
// §2.5 for the `az identity federated-credential create` step that follows.

targetScope = 'resourceGroup'

@allowed(['dev', 'test', 'prod'])
@description('Environment')
param env string

@description('Location for the resource(s)')
param location string = resourceGroup().location

@description('Tags applied to all resources')
param tags object = {}

// Matches docs/02-Architecture.md §3.3's eight microservices and the MI
// names in docs/naming.md. web-frontend is included even though it has no
// server-side Azure calls today, per the implementation guide's explicit
// Phase 1 scope — drop it here if that turns out to be unnecessary.
var serviceNames = [
  'catalog-svc'
  'review-svc'
  'moderation-worker'
  'assistant-svc'
  'admin-bff'
  'notification-svc'
  'analytics-collector'
  'web-frontend'
]

resource managedIdentities 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = [for svc in serviceNames: {
  name: 'mi-${svc}-${env}'
  location: location
  tags: tags
}]

output managedIdentities array = [for (svc, i) in serviceNames: {
  service: svc
  name: managedIdentities[i].name
  id: managedIdentities[i].id
  principalId: managedIdentities[i].properties.principalId
  clientId: managedIdentities[i].properties.clientId
}]
