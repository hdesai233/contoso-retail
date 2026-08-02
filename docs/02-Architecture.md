# Architecture Document
## Contoso Smart Retail Insights Platform

**Version:** 1.0
**Companion to:** `01-Requirements.md`

---

## 1. Architecture goals and the principles behind them

Every choice below traces back to one of these principles:

1. **Cloud-native and managed-first.** Prefer PaaS over IaaS, prefer fully managed over self-hosted, prefer consumption-tier over reserved-tier until proven otherwise.
2. **Zero trust, identity-first.** No password-based service auth. Every workload has a Managed Identity. Every secret lives in Key Vault. Every network hop authenticates.
3. **Composable microservices, not a distributed monolith.** Services own their data. They communicate via well-defined APIs and async events. No shared databases.
4. **Event-driven where it makes sense, RPC where it doesn't.** User-facing reads are synchronous REST. Cross-service writes that don't need an immediate answer are events.
5. **Polyglot persistence on purpose.** Use the right store: Cosmos for catalog (geo-scale, flexible schema), SQL for orders (transactional, relational), Blob for images (cheap binary), Redis for hot reads.
6. **Observability is a feature, not a layer.** Every request gets a trace ID. Every service surfaces RED metrics. Dashboards exist before incidents.
7. **Infra is code, deployments are pipelines.** No click-ops in test or prod.

## 2. Reference architecture at a glance

```
                                        ┌──────────────────┐
                          shoppers ────►│ Azure Front Door │  (TLS, geo-routing, caching)
                                        │   Standard/Prem  │
                                        └────────┬─────────┘
                                                 ▼
                              ┌─────────────────────────────────┐
                              │ Application Gateway + WAF (v2)  │  (OWASP rules, prevention mode)
                              └────────┬────────────────────────┘
                                       │  Private Link to AKS ingress
                                       ▼
            ┌──────────────────────────────────────────────────────────┐
            │   Azure Kubernetes Service (AKS), zone-redundant         │
            │   ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐    │
            │   │ catalog-svc │ │ review-svc  │ │ assistant-svc   │    │
            │   └─────────────┘ └─────────────┘ └─────────────────┘    │
            │   ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐    │
            │   │ moderation- │ │ admin-bff   │ │ web frontend    │    │
            │   │   worker    │ │             │ │ (React/Vite)    │    │
            │   └─────────────┘ └─────────────┘ └─────────────────┘    │
            │   NGINX/Application Routing add-on as cluster ingress    │
            └────┬────────────┬─────────────────┬───────────────┬──────┘
                 │ MI         │ MI              │ MI            │ MI
                 ▼            ▼                 ▼               ▼
        ┌─────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
        │ Cosmos DB   │ │ Azure SQL    │ │ Blob Storage │ │ Redis Cache  │
        │ (NoSQL)     │ │ (PaaS)       │ │ + Files      │ │ (Enterprise) │
        └─────────────┘ └──────────────┘ └──────────────┘ └──────────────┘
                 │              │                │
                 │              │                │
        ┌────────┴──────────────┴────────────────┴────────────┐
        │  Azure Service Bus (commands)  •  Event Hubs (telemetry) │
        └──────────────────────┬───────────────────────────────┘
                               ▼
              ┌──────────────────────────────────────┐
              │ Stream Analytics → ADLS Gen2 → Synapse│
              │           ↘ Power BI dashboards       │
              └──────────────────────────────────────┘

   AI plane (private endpoints, MI auth):
   ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
   │ Azure OpenAI     │ │ Azure AI Search  │ │ AI Services      │
   │ (GPT + embed)    │ │ (vector + BM25)  │ │ (Language,Vision,│
   │                  │ │                  │ │ Content Safety)  │
   └──────────────────┘ └──────────────────┘ └──────────────────┘

   Cross-cutting:
   • Microsoft Entra ID (workforce) + External ID (customers)
   • Azure Key Vault (secrets/keys/certs) — referenced via MI
   • Azure Container Registry (private, customer-managed keys)
   • Microsoft Defender for Cloud + Microsoft Sentinel
   • Azure Monitor, App Insights, Log Analytics
   • Azure Policy + Management Groups
```

See the rendered diagram at the end of this document.

## 3. Logical building blocks

### 3.1 Edge and ingress
**Azure Front Door (Standard or Premium).** Handles TLS termination at the edge, geo-routing, and static content caching. Premium adds managed WAF and Private Link to origins. Provides a stable anycast IP and protects against L7 DDoS.

**Application Gateway v2 with WAF.** A regional reverse proxy with OWASP Core Rule Set. Sits in a dedicated subnet inside the platform VNet. In prod, Front Door reaches it via Private Link; in dev you can connect via a restricted public IP for simplicity.

> Why two layers? Front Door gives global anycast and edge caching; Application Gateway gives regional WAF, header rewrites, and URL-based routing into the cluster. You can collapse to one in non-prod.

### 3.2 Compute: AKS
**Azure Kubernetes Service** is the compute backbone. Choices:
- **Cluster topology:** one cluster per environment, zone-redundant in prod (3 zones).
- **Node pools:** a `system` pool (taints `CriticalAddonsOnly`) and at least one `user` pool. Add a `gpu` pool only if you self-host any models (not needed since we use Azure OpenAI).
- **Networking:** **Azure CNI Overlay** so pods can reach Azure services via Private Endpoints without bloating the IP range.
- **Identity:** **Microsoft Entra Workload Identity** (the OIDC federation model). Each Deployment binds to a Kubernetes ServiceAccount which is federated to a User-Assigned Managed Identity.
- **Ingress:** the **Application Routing add-on** (managed NGINX) for simplicity. Alternative: Application Gateway Ingress Controller (AGIC) if you want the gateway itself inside the cluster.
- **Add-ons:** Azure Monitor for containers, Defender for Containers, Azure Policy, Key Vault Secrets Store CSI driver.
- **Scaling:** Horizontal Pod Autoscaler on CPU + custom metric; Cluster Autoscaler on node pool. KEDA for event-driven scaling of the moderation worker based on Service Bus queue depth.

> Why AKS over Azure Container Apps or App Service? Per Andersson Ch. 3, ACA is great for simple microservices with serverless billing. AKS wins when you want richer control, custom networking, and the full Kubernetes ecosystem. Since this is a *learning* project that covers Kubernetes deeply, AKS is the right call. In a smaller real-world project you might pick ACA.

### 3.3 Microservices (the eight services)
Each runs as a Deployment in its own namespace, exposes a REST API (and gRPC where it helps), reads its config from environment variables, fetches secrets via the CSI driver from Key Vault, and authenticates outbound calls with its Managed Identity.

| Service | Tech | Responsibility |
|---|---|---|
| `web-frontend` | React + Vite, served by NGINX | Public PWA. Calls API gateway only. |
| `catalog-svc` | .NET 8 minimal API (or Node/Fastify) | Read-only product catalog API. Cosmos read, Redis cache-aside. |
| `review-svc` | .NET 8 / Node | Review CRUD. Writes to Cosmos, publishes events to Event Hubs. |
| `moderation-worker` | .NET 8 worker / Python | Consumes new-review queue, calls AI Language / Vision / Content Safety, updates status. KEDA-scaled. |
| `assistant-svc` | Python FastAPI (LangChain or semantic-kernel) | Chat orchestration. Calls Azure OpenAI + AI Search. |
| `admin-bff` | .NET 8 | Backend-for-frontend for the admin UI. Strict RBAC. |
| `notification-svc` | Node | Sends email confirmations and ops alerts. Uses ACS / Logic App. |
| `analytics-collector` | Lightweight Go / Node | Receives raw client events; forwards to Event Hubs. |

> Polyglot is intentional pedagogically. In a real shop you'd pick one or two stacks. Claude Code is comfortable with all of these.

### 3.4 Data plane

**Azure Cosmos DB for NoSQL** holds products and reviews.
- Database: `contoso-retail`.
- Containers: `products` (PK `/categoryId`), `reviews` (PK `/productId`), `chat-history` (PK `/userId`, TTL 30d).
- Throughput: per-container autoscale, 1k → 4k RU/s in prod.
- Consistency: **Session** consistency (default).
- Backup: continuous (point-in-time restore).
- Security: Private Endpoint only, AAD auth via Managed Identity, RBAC role assignments per service. **No primary keys distributed to apps.**

**Azure SQL Database** holds the User, Order, and audit-log relational data.
- Tier: General Purpose serverless in non-prod, Business Critical zone-redundant in prod.
- Auth: Entra-only authentication (no SQL logins). Service connects via MI.
- Always Encrypted with secure enclaves for PII columns (email, phone).
- TDE always on, with CMK in prod.

**Azure Blob Storage** for review images.
- Account kind StorageV2, RA-GZRS in prod.
- Container `reviews-images` (private). Lifecycle: hot → cool at 90 days, archive at 1 year.
- Customer images are uploaded via **SAS tokens** generated by `review-svc` (the service never proxies the upload). Tokens are short-lived (15 min) and scoped to a single blob path.
- CDN: Front Door serves processed thumbnails from a separate `public-thumbnails` container after virus scan + content safety passes.

**Azure Cache for Redis** for hot product reads and rate-limit counters.
- Tier: Standard in non-prod, Premium with VNet injection or Enterprise with Private Endpoint in prod.

### 3.5 Async messaging

**Azure Service Bus (Standard)** for command-style messaging that needs guaranteed delivery, ordering, and dead-lettering.
- Queue `review-moderation-jobs` consumed by `moderation-worker`. KEDA scales the deployment on queue depth.
- Topic `review-status-changed` with subscriptions for `notification-svc` and the analytics path.

**Azure Event Hubs** for high-throughput telemetry and analytics events.
- `domain-events` hub: every domain event lands here.
- Partition count tuned for throughput; Capture turned on to land Avro/Parquet in ADLS Gen2.

**Azure Event Grid** for resource-level events (e.g., Blob upload triggers a Function for image preprocessing).

> Why three messaging services? They solve different problems. Service Bus = commands/transactions. Event Hubs = telemetry/streaming. Event Grid = system/resource events. Andersson Ch. 10 covers all three; use them as the book describes.

### 3.6 AI plane

**Azure OpenAI Service.**
- Models deployed: a GPT-4-class chat model (e.g., `gpt-4o`) and an embedding model (`text-embedding-3-large`).
- Deployment SKU: PTU (provisioned) in prod for predictable latency; standard pay-as-you-go in dev.
- Auth: Managed Identity from `assistant-svc` and `moderation-worker`.
- Networking: Private Endpoint, public access disabled in prod.
- Rate limits enforced at APIM layer per user and per service.

**Azure AI Search.**
- One service per environment. Premium tier in prod (semantic ranking and private endpoint).
- Indexes: `products-index` with `vector_description`, `vector_features` fields populated from the catalog. Indexer pulls from Cosmos.
- The assistant performs hybrid search (BM25 + vector + semantic re-ranking) then composes the LLM prompt.

**Azure AI Services (multi-service resource).** Single endpoint for:
- **AI Language**: sentiment, key phrase, PII detection.
- **AI Vision**: tags, OCR if needed, adult/racy/gory content scoring.
- **AI Content Safety**: text and image safety with severity scores.

**Image moderation flow** (gives you a complete picture of the AI plane):
1. Client gets a SAS to `reviews-images/pending/{guid}.jpg`.
2. Client PUTs the image directly to Blob.
3. Blob `BlobCreated` event hits Event Grid → triggers a Function or queues a Service Bus message.
4. `moderation-worker` downloads, runs Vision + Content Safety, persists scores.
5. If below thresholds, image is copied to `reviews-images/approved/...` and a thumbnail is generated; the parent review status is updated.
6. Domain event published to Event Hubs.

### 3.7 Analytics plane

**Real-time path**
Event Hubs `domain-events` → **Stream Analytics** job with 1-minute tumbling windows → output to:
- Power BI streaming dataset (live tiles).
- Cosmos DB `realtime-metrics` container (queryable by the admin UI).

**Batch path**
Event Hubs Capture → **ADLS Gen2** (Parquet) → **Synapse Analytics**:
- Serverless SQL pool for ad hoc exploration over the lake.
- A dedicated SQL pool or Spark pool for the curated star schema.
- Synapse pipelines (formerly Data Factory) orchestrate nightly:
  - Catalog snapshot from Cosmos via Change Feed → bronze layer.
  - Reviews enriched with sentiment → silver layer.
  - Star schema and aggregates → gold layer.
- **Microsoft Purview** registers and classifies datasets across Cosmos, SQL, Blob, and Synapse.

**Visualization**
- Power BI workspace per environment.
- Datasets refresh on a schedule + real-time streaming dataset for the live tile.
- Row-level security so internal users only see categories they own.

> Microsoft Fabric vs Synapse: this project uses Synapse because Andersson Ch. 7 maps directly to it. If you want a Fabric stretch goal, that's listed in `03-Implementation-Guide.md` Phase 5 bonus.

### 3.8 Identity model

Two distinct identity systems, one mental model.

**Workforce identity — Microsoft Entra ID (the corp tenant).**
Used by: platform engineers, merchandisers, moderators.
Enforced via Conditional Access:
- MFA required for all roles.
- Compliant Intune device required for `Moderator` and `Platform-Admin`.
- Sign-in risk policies block high-risk sign-ins.
- Privileged Identity Management (PIM) for any `Owner`, `Contributor`, or `User Access Administrator` role on Azure resources — just-in-time elevation only.

**Customer identity — Microsoft Entra External ID** (the customer-facing tenant, formerly Azure AD B2C).
- Local accounts (email+password) and social federation (Google, Microsoft).
- User flows for sign-up, sign-in, password reset, profile edit.
- Custom branding to match the Contoso theme.
- The `web-frontend` uses the MSAL.js library; APIs validate JWTs.

**Workload identity — Managed Identities for every service.**
- User-Assigned MI per service, federated to the service's Kubernetes ServiceAccount.
- RBAC role assignments per scope; e.g., `review-svc` MI gets:
  - `Cosmos DB Built-in Data Contributor` on the `reviews` container only.
  - `Azure Service Bus Data Sender` on the `review-moderation-jobs` queue.
  - `Storage Blob Data Contributor` on the `reviews-images` container only.

**API security**
- All north-south traffic terminates at the WAF; user JWTs are validated at **Azure API Management** which sits in front of AKS ingress for the public API surface.
- APIM applies rate limits, quotas, request validation, and adds correlation IDs.
- Inside the cluster, services validate the propagated JWT again (defense in depth) and enforce business RBAC.

### 3.9 Networking

```
Subscription / Management Group
└── Resource Group: rg-contoso-prod-eus2
    └── VNet: vnet-contoso-prod-eus2 (10.20.0.0/16)
        ├── snet-aks-systempool    (10.20.0.0/22)
        ├── snet-aks-userpool      (10.20.4.0/22)
        ├── snet-aks-podcidr       (10.244.0.0/16, CNI overlay)
        ├── snet-appgw             (10.20.8.0/24)
        ├── snet-pe                (10.20.9.0/24)   ← Private Endpoints
        ├── snet-apim              (10.20.10.0/24)
        ├── snet-jumpbox           (10.20.11.0/27)  ← only via Bastion
        └── AzureBastionSubnet     (10.20.11.32/27)
```

- All Azure data services accessed via **Private Endpoints** in `snet-pe`.
- Private DNS zones linked to the VNet (one per service type, e.g., `privatelink.documents.azure.com`).
- NSGs on every subnet, deny-all-by-default, explicit allows.
- Azure Firewall optional but recommended in prod for egress filtering (skip in dev to save cost).
- Hub-and-spoke is overkill for one environment but is the recommended next step — a `hub-vnet` peered to each environment VNet, hosting the Firewall, Bastion, and shared DNS.

### 3.10 DevOps and platform automation

**Source of truth: GitHub.** Repo layout:

```
contoso-retail/
├── apps/
│   ├── catalog-svc/
│   ├── review-svc/
│   ├── moderation-worker/
│   ├── assistant-svc/
│   ├── admin-bff/
│   ├── notification-svc/
│   ├── analytics-collector/
│   └── web-frontend/
├── infra/
│   ├── main.bicep
│   ├── modules/
│   │   ├── aks.bicep
│   │   ├── cosmos.bicep
│   │   ├── sql.bicep
│   │   ├── storage.bicep
│   │   ├── network.bicep
│   │   ├── keyvault.bicep
│   │   ├── ai-search.bicep
│   │   ├── openai.bicep
│   │   ├── eventhubs.bicep
│   │   ├── stream-analytics.bicep
│   │   ├── synapse.bicep
│   │   ├── apim.bicep
│   │   ├── front-door.bicep
│   │   ├── observability.bicep
│   │   └── identity.bicep
│   └── env/
│       ├── dev.bicepparam
│       ├── test.bicepparam
│       └── prod.bicepparam
├── k8s/
│   ├── base/        ← Kustomize base manifests
│   └── overlays/
│       ├── dev/
│       ├── test/
│       └── prod/
├── .github/workflows/
│   ├── ci-apps.yml
│   ├── ci-infra.yml
│   ├── cd-dev.yml
│   ├── cd-test.yml
│   └── cd-prod.yml
├── docs/
│   ├── 01-Requirements.md
│   ├── 02-Architecture.md
│   ├── 03-Implementation-Guide.md
│   └── 04-Claude-Code-Playbook.md
├── azure.yaml          ← azd config
├── CLAUDE.md           ← project-level instructions for Claude Code
└── README.md
```

**CI/CD flow.**
1. PR opened → unit tests run, container images built (no push), `bicep what-if` runs.
2. Merge to `main` → images pushed to ACR with `sha`+`semver` tags, signed with Notary v2 → cosign optional.
3. Deploy to dev via `azd deploy` or by `cd-dev.yml` applying Kustomize overlays.
4. Smoke tests run.
5. Manual approval gates promotion to test, then to prod. Bicep what-if posted to the PR for visual review.
6. Rollback = re-run prior workflow run, or `kubectl rollout undo`, plus a Bicep revert if infra changed.

**Federated workload identity** between GitHub Actions and Azure replaces service principal secrets entirely.

### 3.11 Observability

**Azure Monitor + Log Analytics workspace** as the single sink.

| Source | Diagnostic setting target |
|---|---|
| AKS control plane | LA workspace |
| AKS container logs + metrics | Container Insights → same LA workspace |
| AppGw, Front Door, APIM | LA |
| Cosmos DB, SQL, Storage, Key Vault | LA |
| Activity logs | LA + Storage (long-term) |

**Application Insights** instance per service (or one shared with cloud_RoleName per service). OpenTelemetry SDK in each service. W3C `traceparent` propagated through HTTP/gRPC/queue messages.

**Workbooks**:
- "Service health" workbook: RED metrics per service.
- "AI usage" workbook: tokens, latency, errors per model deployment.
- "Cost-to-serve" workbook: cost per 1k reviews, cost per 1k chats.

**Alerts** are managed in Bicep and tied to **Action Groups** that page on Teams/Slack + Email + SMS for prod.

**Microsoft Sentinel** sits on the same LA workspace for SOC features (analytics rules, hunting queries, automation playbooks).

### 3.12 Cost model (rough monthly estimate)

| Tier | Component | Est. monthly cost |
|---|---|---|
| **Dev** | AKS B2s nodes (2), Cosmos free tier, AI Search Free, OpenAI pay-as-you-go ~$10, Storage, KV, App Insights | **~$100–150** |
| **Test** | AKS D4s_v5 (2-3 nodes), Cosmos autoscale 1k RU, AI Search Basic, OpenAI ~$50, AppGw v2, APIM Dev | **~$500–700** |
| **Prod** | AKS zone-redundant D4s_v5 (3+ nodes), Cosmos autoscale 4k RU/container, AI Search S1, OpenAI PTU 50, AppGw v2 Premium, APIM Standard v2, Front Door Premium, SQL BC GP, Sentinel | **~$2,500–4,000** |

These are order-of-magnitude. Run **Azure Pricing Calculator** with your real region and SKUs before any sizing decision.

## 4. Cross-cutting design decisions and trade-offs

| Decision | Choice | Alternative | Why we chose this |
|---|---|---|---|
| Compute platform | AKS | Container Apps, App Service | Maximum learning surface area + future flexibility |
| Auth for service-to-service | Managed Identity + Workload Identity Federation | Service principals with secrets | No secrets to rotate, identity is the perimeter |
| Catalog database | Cosmos DB (NoSQL API) | Azure SQL | Catalog is read-heavy, geo-distributable, flexible schema |
| Transactional DB | Azure SQL | Postgres Flexible Server | Tighter integration with Always Encrypted + book coverage |
| Messaging | Service Bus + Event Hubs + Event Grid | Just one or two | They solve different problems; learning each is valuable |
| LLM | Azure OpenAI | Self-hosted Llama on AKS GPU | PaaS scales, Azure compliance, lower ops burden |
| Vector store | Azure AI Search | Cosmos DB vector, PostgreSQL pgvector | Hybrid search + semantic ranker baked in |
| Warehouse | Synapse Analytics | Microsoft Fabric | Matches the book; Fabric listed as stretch |
| Edge | Front Door + AppGw | Just AppGw, or Front Door Premium alone | Demonstrates layered defense |
| IaC | Bicep | Terraform | First-party, AAD-native, simpler for Azure-only |
| Cluster ingress | App Routing add-on (managed NGINX) | AGIC | One less thing to operate; AGIC is a Phase 6 swap option |

## 5. Security architecture (Zero Trust applied)

1. **Verify explicitly.** Conditional Access policies for users; MI tokens with audience scoping for services. JWT validated at every hop.
2. **Use least-privilege access.** RBAC per data-plane action, not subscription-level Contributor. Just-in-time elevation via PIM.
3. **Assume breach.**
   - Private Endpoints only in prod — no public network access to any data store.
   - All egress through Firewall (prod stretch goal).
   - Defender for Cloud + Defender plans for Containers, Key Vault, SQL, Storage, App Service.
   - Sentinel rules for impossible travel, mass key access, container privilege escalation.

**Threat model summary** (STRIDE per major flow):

| Flow | Threat | Mitigation |
|---|---|---|
| Public web traffic | Volumetric DDoS | Front Door + DDoS Protection Standard |
| Public API | OWASP injection/XSS | WAF (prevention mode) + APIM validation |
| Review submission | Image upload of malware | AI Content Safety + Defender for Storage malware scan |
| Service → DB | Credential theft | Managed Identity, no secrets, NSG + Private Endpoint |
| Insider misuse | Mass data export | PIM, Sentinel UEBA, Customer Lockbox if eligible |
| AI prompt injection | Indirect prompt injection from review text | Strict system prompt, retrieved-content sanitization, output filters, content safety on output |

## 6. Disaster recovery design

- **Cosmos DB:** continuous backup, restore-to-region.
- **Azure SQL:** auto-failover group to the paired region, geo-restore.
- **Blob Storage:** RA-GZRS for the prod review-images account.
- **AKS:** redeploy cluster from Bicep into paired region; reconfigure DNS at Front Door.
- **Key Vault:** soft-delete + purge protection on; replicate critical secrets to a paired KV.
- **DR drill:** quarterly, runbook lives in `/docs/runbooks/dr.md`.

## 7. Phased rollout (what to build first)

Six phases — described in detail in `03-Implementation-Guide.md`:

0. Foundation (subscriptions, tooling, Bicep skeleton).
1. Identity, network, secrets baseline.
2. Containers, AKS, first microservice.
3. Data plane.
4. AI plane.
5. Analytics plane.
6. Hardening, observability, cost, DR.

## 8. Rendered architecture diagram

See `architecture-diagram.html` (open in a browser) for a clickable layered view. A simplified data-flow diagram is also embedded in the implementation guide for reference at each phase.

---

*Next: read `03-Implementation-Guide.md` for the step-by-step build plan.*
