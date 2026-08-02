# Naming conventions

CAF-style naming, per `CLAUDE.md`. This document is the source of truth for
exact resource names — Bicep modules under `infra/modules/` should read names
from here rather than inventing their own when they move from `TODO` to
implemented.

## Pattern

```
{abbr}-{workload}-{env}-{region}[-{instance}]
```

| Token | Value |
|---|---|
| `abbr` | CAF resource-type abbreviation ([Microsoft Learn reference](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)) |
| `workload` | `contoso` (fixed — matches `param workload` in `main.bicep`) |
| `env` | `dev`, `test`, or `prod` (matches `param env` in `main.bicep`) |
| `region` | `eus2` (East US 2 — the only region in scope; DR fails over to a paired region but does not get its own name set until a DR deployment is actually stood up) |
| `instance` | Two-digit zero-padded suffix (`01`, `02`, …), only where more than one instance of a resource type can exist in the same RG (e.g. Key Vault, Storage). Omitted otherwise. |

**Exceptions to the pattern:**
- **No-hyphen resources** (ACR, Storage accounts) — Azure disallows hyphens, so tokens are concatenated: `{abbr}{workload}{env}{region}[{instance}]`.
- **Global resources** (Front Door, Entra External ID tenant) — these are not regional, so `region` is dropped: `{abbr}-{workload}-{env}`.
- **Length-constrained resources** (Key Vault ≤ 24 chars, Storage ≤ 24 chars, ACR ≤ 50 chars) — verify the rendered name against the limit before use; see the per-resource table below for confirmed lengths at `eus2`.

## Fixed tokens

| Environment | `env` | Region | Region abbr | Resource group |
|---|---|---|---|---|
| Development | `dev` | East US 2 | `eus2` | `rg-contoso-dev-eus2` |
| Test | `test` | East US 2 | `eus2` | `rg-contoso-test-eus2` |
| Production | `prod` | East US 2 | `eus2` | `rg-contoso-prod-eus2` |

## Resource names by type and environment

### Foundation, identity, and networking (Phase 0–1)

| Resource | Abbr | Module | dev | test | prod |
|---|---|---|---|---|---|
| Resource group | `rg` | — | `rg-contoso-dev-eus2` | `rg-contoso-test-eus2` | `rg-contoso-prod-eus2` |
| Virtual network | `vnet` | `network.bicep` | `vnet-contoso-dev-eus2` | `vnet-contoso-test-eus2` | `vnet-contoso-prod-eus2` |
| Subnet — AKS system pool | `snet` | `network.bicep` | `snet-aks-systempool` | `snet-aks-systempool` | `snet-aks-systempool` |
| Subnet — AKS user pool | `snet` | `network.bicep` | `snet-aks-userpool` | `snet-aks-userpool` | `snet-aks-userpool` |
| Subnet — Application Gateway | `snet` | `network.bicep` | `snet-appgw` | `snet-appgw` | `snet-appgw` |
| Subnet — Private Endpoints | `snet` | `network.bicep` | `snet-pe` | `snet-pe` | `snet-pe` |
| Subnet — APIM | `snet` | `network.bicep` | `snet-apim` | `snet-apim` | `snet-apim` |
| Subnet — jumpbox | `snet` | `network.bicep` | `snet-jumpbox` | `snet-jumpbox` | `snet-jumpbox` |
| Subnet — Bastion (fixed name required by Azure) | — | `network.bicep` | `AzureBastionSubnet` | `AzureBastionSubnet` | `AzureBastionSubnet` |
| Network security group (per subnet) | `nsg` | `network.bicep` | `nsg-{subnet-name}-dev-eus2` | `nsg-{subnet-name}-test-eus2` | `nsg-{subnet-name}-prod-eus2` |
| Private DNS zone | — | `network.bicep` | `privatelink.<service>.azure.com` (fixed Azure names, one zone per data-service type, linked to the VNet above) | same | same |
| Key Vault (Premium, 24 char max) | `kv` | `keyvault.bicep` | `kv-contoso-dev-eus2-01` (22 chars) | `kv-contoso-test-eus2-01` (23 chars) | `kv-contoso-prod-eus2-01` (23 chars) |
| Log Analytics workspace | `log` | `observability.bicep` | `log-contoso-dev-eus2` | `log-contoso-test-eus2` | `log-contoso-prod-eus2` |
| Application Insights (per-service, `cloud_RoleName` = service name) | `appi` | `observability.bicep` | `appi-contoso-dev-eus2` | `appi-contoso-test-eus2` | `appi-contoso-prod-eus2` |
| Action group | `ag` | `observability.bicep` | `ag-contoso-dev-eus2` | `ag-contoso-test-eus2` | `ag-contoso-prod-eus2` |
| Defender for Cloud plans (subscription-level, not a named resource) | — | `defender.bicep` | n/a | n/a | n/a |

### Compute (Phase 2)

| Resource | Abbr | Module | dev | test | prod |
|---|---|---|---|---|---|
| AKS cluster | `aks` | `aks.bicep` | `aks-contoso-dev-eus2` | `aks-contoso-test-eus2` | `aks-contoso-prod-eus2` |
| Container Registry (no hyphens, ≤ 50 chars) | `acr` | `acr.bicep` | `acrcontosodeveus2` | `acrcontosotesteus2` | `acrcontosoprodeus2` |

### User-assigned managed identities (workload identity, one per microservice)

`identity.bicep` — pattern `mi-{service-name}-{env}` (region omitted; MIs are tied to the AKS cluster's workload identity federation, not a region-scoped data plane):

| Service | dev | test | prod |
|---|---|---|---|
| `catalog-svc` | `mi-catalog-svc-dev` | `mi-catalog-svc-test` | `mi-catalog-svc-prod` |
| `review-svc` | `mi-review-svc-dev` | `mi-review-svc-test` | `mi-review-svc-prod` |
| `moderation-worker` | `mi-moderation-worker-dev` | `mi-moderation-worker-test` | `mi-moderation-worker-prod` |
| `assistant-svc` | `mi-assistant-svc-dev` | `mi-assistant-svc-test` | `mi-assistant-svc-prod` |
| `admin-bff` | `mi-admin-bff-dev` | `mi-admin-bff-test` | `mi-admin-bff-prod` |
| `notification-svc` | `mi-notification-svc-dev` | `mi-notification-svc-test` | `mi-notification-svc-prod` |
| `analytics-collector` | `mi-analytics-collector-dev` | `mi-analytics-collector-test` | `mi-analytics-collector-prod` |
| `web-frontend`* | `mi-web-frontend-dev` | `mi-web-frontend-test` | `mi-web-frontend-prod` |

\* `web-frontend` is a static SPA with no server-side Azure calls today; skip provisioning its MI until it actually needs one — don't create it speculatively.

### Data plane (Phase 3)

| Resource | Abbr | Module | dev | test | prod |
|---|---|---|---|---|---|
| Cosmos DB account | `cosmos` | `cosmos.bicep` | `cosmos-contoso-dev-eus2` | `cosmos-contoso-test-eus2` | `cosmos-contoso-prod-eus2` |
| Cosmos DB database | — | `cosmos.bicep` | `contoso-retail` | `contoso-retail` | `contoso-retail` |
| Cosmos DB containers | — | `cosmos.bicep` | `products`, `reviews`, `chat-history`, `realtime-metrics` | same | same |
| SQL logical server | `sql` | `sql.bicep` | `sql-contoso-dev-eus2` | `sql-contoso-test-eus2` | `sql-contoso-prod-eus2` |
| SQL database | `sqldb` | `sql.bicep` | `sqldb-contoso-dev-eus2` | `sqldb-contoso-test-eus2` | `sqldb-contoso-prod-eus2` |
| Storage account — review images (no hyphens, ≤ 24 chars) | `st` | `storage.bicep` | `stcontosodeveus201` (18 chars) | `stcontosotesteus201` (19 chars) | `stcontosoprodeus201` (19 chars) |
| Blob container — private originals | — | `storage.bicep` | `reviews-images` | `reviews-images` | `reviews-images` |
| Blob container — public thumbnails | — | `storage.bicep` | `public-thumbnails` | `public-thumbnails` | `public-thumbnails` |
| Redis cache | `redis` | `redis.bicep` | `redis-contoso-dev-eus2` | `redis-contoso-test-eus2` | `redis-contoso-prod-eus2` |

### Messaging (Phase 3)

| Resource | Abbr | Module | dev | test | prod |
|---|---|---|---|---|---|
| Service Bus namespace | `sbns` | `service-bus.bicep` | `sbns-contoso-dev-eus2` | `sbns-contoso-test-eus2` | `sbns-contoso-prod-eus2` |
| Service Bus queue | `sbq` | `service-bus.bicep` | `sbq-review-moderation-jobs` | same | same |
| Service Bus topic | `sbt` | `service-bus.bicep` | `sbt-review-status-changed` | same | same |
| Event Hubs namespace | `evhns` | `eventhubs.bicep` | `evhns-contoso-dev-eus2` | `evhns-contoso-test-eus2` | `evhns-contoso-prod-eus2` |
| Event Hub | `evh` | `eventhubs.bicep` | `evh-domain-events` | same | same |
| Event Grid topic (Blob → moderation trigger) | `evgt` | not yet a module — likely added to `storage.bicep` | `evgt-contoso-dev-eus2` | `evgt-contoso-test-eus2` | `evgt-contoso-prod-eus2` |

### AI plane (Phase 4)

| Resource | Abbr | Module | dev | test | prod |
|---|---|---|---|---|---|
| Azure OpenAI account | `openai` | `openai.bicep` | `openai-contoso-dev-eus2` | `openai-contoso-test-eus2` | `openai-contoso-prod-eus2` |
| Azure AI Search service | `srch` | `ai-search.bicep` | `srch-contoso-dev-eus2` | `srch-contoso-test-eus2` | `srch-contoso-prod-eus2` |
| Azure AI Search index | — | `ai-search.bicep` | `products-index` | same | same |
| AI Services (multi-service: Language, Vision, Content Safety) | `ais` | `ai-services.bicep` | `ais-contoso-dev-eus2` | `ais-contoso-test-eus2` | `ais-contoso-prod-eus2` |

### Analytics plane (Phase 5)

| Resource | Abbr | Module | dev | test | prod |
|---|---|---|---|---|---|
| Stream Analytics job | `asa` | `stream-analytics.bicep` | `asa-contoso-dev-eus2` | `asa-contoso-test-eus2` | `asa-contoso-prod-eus2` |
| ADLS Gen2 storage account (no hyphens, ≤ 24 chars) | `dls` | `storage-adls.bicep` | `dlscontosodeveus2` (17 chars) | `dlscontosotesteus2` (18 chars) | `dlscontosoprodeus2` (18 chars) |
| ADLS containers (bronze/silver/gold) | — | `storage-adls.bicep` | `bronze`, `silver`, `gold` | same | same |
| Synapse workspace | `synw` | `synapse.bicep` | `synw-contoso-dev-eus2` | `synw-contoso-test-eus2` | `synw-contoso-prod-eus2` |
| Synapse dedicated SQL pool | `syndp` | `synapse.bicep` | `syndp-contoso-dev-eus2` | `syndp-contoso-test-eus2` | `syndp-contoso-prod-eus2` |
| Microsoft Purview account | `pview` | `purview.bicep` | `pview-contoso-dev-eus2` | `pview-contoso-test-eus2` | `pview-contoso-prod-eus2` |
| Power BI workspace (not an ARM resource — Fabric/PBI workspace name) | — | n/a | `Contoso Retail — Dev` | `Contoso Retail — Test` | `Contoso Retail — Prod` |

### Edge and API (Phase 6)

| Resource | Abbr | Module | dev | test | prod |
|---|---|---|---|---|---|
| Azure Front Door profile (global — no region) | `afd` | `front-door.bicep` | `afd-contoso-dev` | `afd-contoso-test` | `afd-contoso-prod` |
| Front Door WAF policy (global — no region) | `waf` | `front-door.bicep` | `waf-contoso-dev` | `waf-contoso-test` | `waf-contoso-prod` |
| API Management | `apim` | `apim.bicep` | `apim-contoso-dev-eus2` | `apim-contoso-test-eus2` | `apim-contoso-prod-eus2` |
| Application Gateway v2 + WAF | `agw` | not yet a module — see note below | `agw-contoso-dev-eus2` | `agw-contoso-test-eus2` | `agw-contoso-prod-eus2` |

> **Note on Application Gateway:** `docs/02-Architecture.md` §3.1 describes an AppGW v2 + WAF layer in front of AKS ingress, but no `infra/modules/appgw.bicep` exists yet and the Phase 6 decision table currently has the App Routing add-on (managed NGINX) as cluster ingress instead. Flag this to the user before implementing — either add a dedicated `appgw.bicep` module using the name above, or drop AppGW from the architecture doc if App Routing add-on is the final decision.

## Notes

- **Instance suffixes** (`-01`, `-02`) are reserved for resources where a second instance is plausible in the same RG (Key Vault, Storage accounts). Singleton resources (AKS, Cosmos, SQL server, etc.) omit it.
- **`dev` may keep public network access** per `CLAUDE.md` rule 2 — this does not change any name, only a network-access property on the same resource.
- Non-ARM, data-plane identifiers (Cosmos containers, Blob containers, Service Bus queues/topics, Event Hub names, ADLS containers) are shared verbatim across environments — only the parent resource name carries the `{env}` token.
- Reference: [CAF resource abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations).
