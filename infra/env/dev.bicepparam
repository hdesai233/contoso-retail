using '../main.bicep'

param workload = 'contoso'
param env      = 'dev'

// This subscription's "Allowed resource deployment regions" policy blocks
// eastus2 — see docs/decisions/ADR-001-dev-region-eastus.md. Dev uses eastus
// until that's resolved; test/prod stay on eastus2 (eus2) per docs/naming.md.
param location   = 'eastus'
param regionAbbr = 'eus'
