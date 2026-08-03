// observability.bicep — Phase 1
// Log Analytics workspace, workspace-based Application Insights, and the
// subscription Activity Log routed to the workspace.
//
// See docs/03-Implementation-Guide.md Phase 1 and docs/naming.md.

targetScope = 'resourceGroup'

@description('Short workload name, e.g. contoso')
param workload string

@allowed(['dev', 'test', 'prod'])
@description('Environment')
param env string

@description('Location for the resource(s)')
param location string = resourceGroup().location

@description('CAF region abbreviation used in resource names — must match `location`. See docs/naming.md.')
param regionAbbr string = 'eus2'

@description('Tags applied to all resources')
param tags object = {}

@minValue(30)
@maxValue(730)
@description('Log Analytics workspace retention in days')
param logRetentionInDays int = 30

var laWorkspaceName = 'log-${workload}-${env}-${regionAbbr}'
var appInsightsName = 'appi-${workload}-${env}-${regionAbbr}'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: laWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionInDays
  }
}

// Workspace-based Application Insights. One shared instance per environment;
// each microservice sets its own OpenTelemetry `cloud_RoleName` rather than
// getting a dedicated App Insights resource — see docs/naming.md.
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
}

// Activity Log is subscription-wide, not resource-group-scoped, so this runs
// as a nested subscription-scoped module. The setting name includes `env` so
// multiple environments sharing one subscription each get their own setting
// instead of overwriting each other's.
module activityLogDiagnostics 'activity-log-diagnostics.bicep' = {
  name: 'activityLogDiagnostics-${env}'
  scope: subscription()
  params: {
    laWorkspaceId: logAnalyticsWorkspace.id
    diagnosticSettingName: 'diag-activity-log-${env}-to-la'
  }
}

output laWorkspaceId string = logAnalyticsWorkspace.id
output laWorkspaceName string = logAnalyticsWorkspace.name
output appInsightsId string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
