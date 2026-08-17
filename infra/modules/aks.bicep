// aks.bicep — Phase 2
// AKS cluster: Workload Identity + OIDC issuer, Application Routing add-on,
// Container Insights + Defender for Containers wired to the shared LA
// workspace, Azure CNI Overlay with Cilium, one system pool + one user pool,
// AcrPull granted to the kubelet identity so image pulls need no credentials.
//
// Node sizing: the system pool has a hard Azure requirement — at least
// 4 vCPU / 4 GB, B-series not supported at all — so it can't be shrunk
// below Standard_D4s_v5-class sizes regardless of environment.
// https://learn.microsoft.com/azure/aks/use-system-pools#system-and-user-node-pools
// The user pool has no such floor; it defaults to Standard_B2s here to keep
// dev cheap, since that's where catalog-svc (a tiny canned-data API for now)
// actually runs. Override systemPoolVmSize/userPoolVmSize per environment as
// real load shows up — see docs/02-Architecture.md §3.12's cost table.
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

@description('Subnet ID (snet-aks-systempool) for the system node pool')
param systemPoolSubnetId string

@description('Subnet ID (snet-aks-userpool) for the user node pool')
param userPoolSubnetId string

@description('Log Analytics workspace resource ID for Container Insights, Defender for Containers, and control-plane diagnostic settings')
param laWorkspaceId string

@description('Name of the existing ACR the kubelet identity gets AcrPull access to')
param acrName string

@allowed(['Free', 'Standard'])
@description('AKS control-plane SKU tier. Free has no SLA and no cost; Standard adds an SLA-backed API server for ~$0.10/hr. Defaults to Free for cost-conscious dev/learning use — consider Standard for prod.')
param skuTier string = 'Free'

@description('VM size for the system node pool. Must stay >= 4 vCPU / 4 GB and non-B-series — Azure requirement, not a cost knob.')
param systemPoolVmSize string = 'Standard_D4s_v5'

@minValue(2)
@description('System pool node count. Azure requires at least 2; 3 is recommended for prod fault tolerance.')
param systemPoolNodeCount int = 2

@description('VM size for the user node pool. No Azure-imposed floor — size for actual workload.')
param userPoolVmSize string = 'Standard_B2s'

@minValue(1)
@description('User pool autoscale minimum node count')
param userPoolMinCount int = 1

@description('User pool autoscale maximum node count')
param userPoolMaxCount int = 3

@description('Pod CIDR for Azure CNI Overlay — not routed via any VNet subnet, so it does not need to avoid the VNet range, only the service CIDR below.')
param podCidr string = '10.244.0.0/16'

@description('Kubernetes service CIDR — must not overlap the VNet (10.20.0.0/16) or podCidr')
param serviceCidr string = '10.100.0.0/16'

@description('DNS service IP — must fall inside serviceCidr')
param dnsServiceIP string = '10.100.0.10'

@description('Availability zones for both node pools. Empty by default (dev/test); set [\'1\',\'2\',\'3\'] for prod per docs/02-Architecture.md §3.2.')
param availabilityZones array = []

var aksName = 'aks-${workload}-${env}-${regionAbbr}'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: aksName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: skuTier
  }
  properties: {
    dnsPrefix: aksName
    nodeResourceGroup: 'rg-${workload}-${env}-${regionAbbr}-aksinfra'
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
      defender: {
        logAnalyticsWorkspaceResourceId: laWorkspaceId
        securityMonitoring: {
          enabled: true
        }
      }
    }
    ingressProfile: {
      webAppRouting: {
        enabled: true
      }
    }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      loadBalancerSku: 'standard'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceId: laWorkspaceId
        }
      }
    }
    agentPoolProfiles: [
      {
        name: 'systempool'
        mode: 'System'
        osType: 'Linux'
        vmSize: systemPoolVmSize
        count: systemPoolNodeCount
        vnetSubnetID: systemPoolSubnetId
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        availabilityZones: availabilityZones
      }
      {
        name: 'userpool'
        mode: 'User'
        osType: 'Linux'
        vmSize: userPoolVmSize
        vnetSubnetID: userPoolSubnetId
        enableAutoScaling: true
        minCount: userPoolMinCount
        maxCount: userPoolMaxCount
        count: userPoolMinCount
        availabilityZones: availabilityZones
      }
    ]
  }
}

// Diagnostic settings for the control plane itself (kube-apiserver,
// kube-controller-manager, kube-scheduler, cluster-autoscaler, guard, ...) —
// separate from Container Insights above, which covers workload/container
// logs and metrics, not control-plane activity.
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${aksName}'
  scope: aks
  properties: {
    workspaceId: laWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
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

// Grants the cluster's kubelet identity AcrPull on the existing registry, so
// image pulls need no credentials — the Bicep equivalent of
// `az aks update --attach-acr`.
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, aks.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

output aksId string = aks.id
output aksName string = aks.name
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
output nodeResourceGroup string = aks.properties.nodeResourceGroup
