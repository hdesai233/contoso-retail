// defender.bicep — Phase 1
// Microsoft Defender for Cloud: foundational CSPM + Defender for Key Vault.
//
// Subscription-scoped, not resource-group-scoped — Microsoft.Security/pricings
// has no `location` or `tags` property and applies to the whole subscription,
// not a single resource group. The stub this replaced had
// `targetScope = 'resourceGroup'`, which is wrong for this resource type and
// would have failed to deploy.
//
// This also means the module is a subscription-wide setting: if dev/test/prod
// share one subscription (as they currently do — see
// docs/decisions/ADR-001-dev-region-eastus.md), only deploy this once, not
// once per environment. Calling it multiple times is harmless (idempotent,
// same two resources every time) but redundant.
//
// See docs/03-Implementation-Guide.md Phase 1.

targetScope = 'subscription'

@allowed(['Free', 'Standard'])
@description('Pricing tier for the foundational Cloud Security Posture Management plan. Free = foundational recommendations/secure score only, no cost. Standard = Defender CSPM (attack path analysis, agentless scanning, etc.), billed.')
param cloudPosturePricingTier string = 'Free'

@allowed(['Free', 'Standard'])
@description('Pricing tier for Defender for Key Vault. Standard is the actual protection plan (threat detection on vault access) and is billed per vault; Free disables it. Defaults to Standard per the Phase 1 spec — switch to Free if cost is a concern on a constrained subscription.')
param keyVaultsPricingTier string = 'Standard'

resource cloudPosture 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'CloudPosture'
  properties: {
    pricingTier: cloudPosturePricingTier
  }
}

resource keyVaultsPlan 'Microsoft.Security/pricings@2024-01-01' = {
  name: 'KeyVaults'
  properties: {
    pricingTier: keyVaultsPricingTier
  }
}

output cloudPosturePlanId string = cloudPosture.id
output keyVaultsPlanId string = keyVaultsPlan.id
