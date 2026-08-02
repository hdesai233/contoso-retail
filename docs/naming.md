# Naming conventions

Pattern: `{abbr}-{workload}-{env}-{region}[-{instance}]`
- `abbr` = CAF resource type abbreviation
- `workload` = `contoso`
- `env` ∈ `{dev, test, prod}`
- `region` = `eus2` (East US 2)

## Common resources

| Resource | Pattern | Example |
|---|---|---|
| Resource Group | `rg-{workload}-{env}-{region}` | `rg-contoso-dev-eus2` |
| Virtual Network | `vnet-{workload}-{env}-{region}` | `vnet-contoso-dev-eus2` |
| AKS cluster | `aks-{workload}-{env}-{region}` | `aks-contoso-dev-eus2` |
| Container Registry (no hyphens) | `acr{workload}{env}{region}` | `acrcontosodeveus2` |
| Key Vault (24 char max) | `kv-{workload}-{env}-{region}-{nn}` | `kv-contoso-dev-eus2-01` |
| Cosmos DB account | `cosmos-{workload}-{env}-{region}` | `cosmos-contoso-dev-eus2` |
| SQL server | `sql-{workload}-{env}-{region}` | `sql-contoso-dev-eus2` |
| Storage account (no hyphens, 24) | `st{workload}{env}{region}{nn}` | `stcontosodeveus201` |
| Redis | `redis-{workload}-{env}-{region}` | `redis-contoso-dev-eus2` |
| Service Bus namespace | `sbns-{workload}-{env}-{region}` | `sbns-contoso-dev-eus2` |
| Event Hubs namespace | `evhns-{workload}-{env}-{region}` | `evhns-contoso-dev-eus2` |
| OpenAI | `openai-{workload}-{env}-{region}` | `openai-contoso-dev-eus2` |
| AI Search | `srch-{workload}-{env}-{region}` | `srch-contoso-dev-eus2` |
| App Insights | `appi-{workload}-{env}-{region}` | `appi-contoso-dev-eus2` |
| Log Analytics | `log-{workload}-{env}-{region}` | `log-contoso-dev-eus2` |
| APIM | `apim-{workload}-{env}-{region}` | `apim-contoso-dev-eus2` |
| Front Door profile | `afd-{workload}-{env}` | `afd-contoso-prod` |
| Managed Identity | `mi-{svc-name}-{env}` | `mi-catalog-svc-dev` |

Reference: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations
