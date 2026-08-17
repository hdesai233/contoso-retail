// container-apps-env.bicep — Phase 2
// Azure Container Apps Managed Environment, Consumption-only (the AKS-cluster
// equivalent per ADR-002 — see that ADR for why AKS was abandoned).
//
// Deliberately NOT a Workload profiles environment: Workload profiles use
// dedicated VM-backed compute and draw from the same subscription VM-family
// vCPU quota pool that blocked AKS. Consumption-only draws from its own
// separate, environment-scoped quota (~100 cores default) — that's the
// entire reason this pivot solves the problem instead of just moving it.
// https://learn.microsoft.com/azure/container-apps/quotas
//
// VNet integration is OFF by default (useVnetIntegration = false). A real
// deployment attempt hit an open, unresolved platform bug:
// https://github.com/microsoft/azure-container-apps/issues/1644 —
// Consumption-only environments with a custom VNet demand subnet delegation
// to Microsoft.App/environments even though Microsoft's own docs say not to
// delegate that subnet. No confirmed fix or root cause as of this writing.
// Delegating anyway was judged too risky: it might silently enroll the
// environment in Workload-profiles-style behavior and reintroduce the exact
// vCPU quota wall this whole pivot exists to avoid — unconfirmed either way.
// snet-aca stays reserved in network.bicep; flip useVnetIntegration to true
// once there's clearer guidance. See the ADR-002 addendum for the full story.
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

@description('Subnet ID (snet-aca) for the environment. Only used when useVnetIntegration is true — see the header comment for why this defaults off.')
param acaSubnetId string = ''

@description('Whether to integrate the environment into acaSubnetId. Defaults false due to an open platform bug — see the header comment.')
param useVnetIntegration bool = false

@description('Name of the existing Log Analytics workspace to route app/system logs to')
param laWorkspaceName string

@description('Internal-only ingress (no public IP). Only meaningful when useVnetIntegration is true — an environment with no VNet integration is always externally reachable. False for now regardless; Phase 2 just needs to prove the round-trip works via curl.')
param internalIngress bool = false

var containerAppsEnvName = 'cae-${workload}-${env}-${regionAbbr}'

resource laWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: laWorkspaceName
}

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: containerAppsEnvName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: useVnetIntegration ? {
      infrastructureSubnetId: acaSubnetId
      internal: internalIngress
    } : null
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: laWorkspace.properties.customerId
        sharedKey: laWorkspace.listKeys().primarySharedKey
      }
    }
    // No workloadProfiles array — that's what keeps this Consumption-only.
  }
}

output containerAppsEnvId string = containerAppsEnv.id
output containerAppsEnvName string = containerAppsEnv.name
output defaultDomain string = containerAppsEnv.properties.defaultDomain
