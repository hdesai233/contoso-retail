// aks.bicep — Phase 2 — CURRENTLY UNUSED, KEPT FOR POSSIBLE FUTURE USE.
//
// This module is fully implemented and was verified against Microsoft Learn
// property-by-property, but this subscription has a hard 6 vCPU total
// regional quota cap (identical across every region it can deploy to) and
// AKS's system node pool has a non-negotiable >=8 vCPU floor (>=4 vCPU x
// >=2 nodes, non-B-series). 8 > 6, so no configuration of this module can
// deploy here. Phase 2 compute pivoted to Azure Container Apps instead —
// see docs/decisions/ADR-002-aks-to-container-apps.md for the full account,
// including the three failed deployment attempts that led to this.
//
// Kept rather than deleted in case the subscription's vCPU quota is ever
// increased and AKS becomes viable again — deleting fully-verified, working
// IaC over an external quota fluke felt wasteful. Revisit before reusing:
// SKU availability and resource-provider registrations may have changed.
//
// AKS cluster: Workload Identity + OIDC issuer, Application Routing add-on,
// Container Insights + Defender for Containers wired to the shared LA
// workspace, Azure CNI Overlay with Cilium, one system pool + one user pool,
// AcrPull granted to the kubelet identity so image pulls need no credentials.
//
// Node sizing: the system pool has a hard Azure requirement — at least
// 4 vCPU / 4 GB, B-series not supported at all — so it can't be shrunk
// below a Standard_D4s-class size regardless of environment.
// https://learn.microsoft.com/azure/aks/use-system-pools#system-and-user-node-pools
// The user pool has no such floor.
//
// Defaults are Standard_D4s_v7 (system) / Standard_D2s_v7 (user) — not v5,
// and not B-series for the user pool either — because this subscription's
// own "allowed VM SKUs" policy separately rejects both Standard_D4s_v5 and
// Standard_B2s (confirmed by a failed deployment: "The VM size of
// Standard_D4s_v5,Standard_B2s is not allowed in your subscription in
// location 'eastus'"). Only newer v7-generation SKUs and a handful of
// specialty families were in that subscription's allow-list; no B-series at
// all. If you're deploying to a different subscription, check its allowed
// SKUs first — see docs/decisions/ADR-001-dev-region-eastus.md for the
// analogous region-policy issue and how it was diagnosed.
// Override systemPoolVmSize/userPoolVmSize per environment/subscription —
// see docs/02-Architecture.md §3.12's cost table for the original intent.
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

@description('VM size for the system node pool. Must stay >= 4 vCPU / 4 GB and non-B-series (AKS requirement) — check it is also in your subscription allowed-SKUs list before changing.')
param systemPoolVmSize string = 'Standard_D4s_v7'

@minValue(2)
@description('System pool node count. Azure requires at least 2; 3 is recommended for prod fault tolerance.')
param systemPoolNodeCount int = 2

@description('VM size for the user node pool. No AKS-imposed floor, but still subject to your subscription allowed-SKUs list.')
param userPoolVmSize string = 'Standard_D2s_v7'

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
