// activity-log-diagnostics.bicep — Phase 1 (subscription-scoped)
// Routes the subscription Activity Log to the shared Log Analytics workspace.
//
// This is a separate file, not inline in observability.bicep, because
// Microsoft.Insights/diagnosticSettings for the Activity Log is a
// subscription-level resource — it cannot be declared directly in a
// resourceGroup-scoped file. observability.bicep invokes this as a
// `scope: subscription()` nested module instead.

targetScope = 'subscription'

@description('Log Analytics workspace resource ID that Activity Log categories are sent to')
param laWorkspaceId string

@description('Name for the subscription Activity Log diagnostic setting. Include env if multiple environments share this subscription, so each gets its own setting instead of overwriting a shared one — see observability.bicep.')
param diagnosticSettingName string

resource activityLogDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingName
  properties: {
    workspaceId: laWorkspaceId
    logs: [
      { category: 'Administrative', enabled: true }
      { category: 'Security', enabled: true }
      { category: 'ServiceHealth', enabled: true }
      { category: 'Alert', enabled: true }
      { category: 'Recommendation', enabled: true }
      { category: 'Policy', enabled: true }
      { category: 'Autoscale', enabled: true }
      { category: 'ResourceHealth', enabled: true }
    ]
  }
}
