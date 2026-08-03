using '../main.bicep'

param workload = 'contoso'
param env      = 'prod'

// Confirm this environment's subscription allows eastus2 before deploying —
// see docs/decisions/ADR-001-dev-region-eastus.md, which found dev's
// subscription does not.
param location   = 'eastus2'
param regionAbbr = 'eus2'
