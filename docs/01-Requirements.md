# Requirements Document
## Contoso Smart Retail Insights Platform

**Version:** 1.0
**Status:** Baseline for learning project
**Author:** You (with Claude Code as pair)
**Audience:** Yourself, three months from now

---

## 1. Executive summary

Contoso Retail is launching an AI-augmented review and recommendation platform. Customers post product reviews (text + photo). Internal teams need real-time insight into sentiment, emerging issues, and demand. The platform must be cloud-native on Azure, secure by default, observable, and cost-controllable.

This document captures functional and non-functional requirements with enough detail that you (or Claude Code) can derive an architecture, work breakdown, and acceptance tests from it.

## 2. Scope

### 2.1 In scope
- Product catalog browsing (read-mostly).
- Authenticated customer accounts.
- Submitting product reviews with optional images.
- AI-driven moderation (toxicity / safety) and sentiment scoring.
- AI shopping assistant chatbot grounded in the product catalog (RAG pattern).
- Real-time analytics stream for review activity.
- Merchandiser dashboard with sentiment trends, top complaints, and category-level KPIs.
- Admin tooling for moderation queue.
- Multi-environment deployment (dev, test, prod) from infrastructure-as-code.
- Operational monitoring and alerting.

### 2.2 Out of scope (explicitly deferred)
- Payments and order processing (stubbed only).
- Shipping/logistics integration.
- Mobile native apps (web responsive is enough).
- Multi-region active-active (single-region with DR plan is enough).
- Marketplace seller onboarding.

### 2.3 Assumptions
- Single Azure subscription, three resource groups (one per environment).
- Workforce identity is Microsoft Entra ID. Customer identity is Microsoft Entra External ID (formerly Azure AD B2C).
- Initial deployment region: East US 2. Paired region for disaster recovery: Central US.
- Initial scale target: 10k MAU, 1k reviews/day, peak 50 RPS on read APIs. Designed to scale 100x.

## 3. Personas and primary user journeys

### 3.1 Personas

| Persona | Description | Top needs |
|---|---|---|
| **Shopper (Sasha)** | Anonymous or signed-in consumer | Browse fast, trust reviews, get help from chatbot |
| **Reviewer (Riya)** | Signed-in customer who has purchased | Post review with photo, see it appear quickly |
| **Merchandiser (Mateo)** | Internal employee, category manager | See sentiment trends, find emerging complaints |
| **Moderator (Maria)** | Internal trust & safety | Review flagged content, take action |
| **Platform engineer (Pat)** | You, the builder | Reliable deploys, clear telemetry, predictable costs |

### 3.2 Primary journeys

**J1. Browse and search the catalog**
> Sasha lands on the homepage, browses categories, opens a product, reads the AI-generated review summary and recent reviews. Page must feel snappy (<1s for catalog reads from cache).

**J2. Sign up and post a review with a photo**
> Riya signs up via External ID (email or social). She uploads a JPEG photo and writes 200 words. Submission goes through AI moderation. If clean, it appears on the PDP within 60 seconds and her account is credited.

**J3. Ask the AI shopping assistant**
> Sasha opens the chat widget and asks "is this jacket good for hiking in cold weather?". The assistant grounds its answer in the catalog and recent reviews using RAG, cites the products it referenced, and stays on-policy (no medical, legal, or off-brand answers).

**J4. Daily sentiment review**
> Mateo opens the Power BI dashboard at 8am. He sees a -12% sentiment dip on a SKU. He drills in and sees the top three complaint clusters (extracted by the AI pipeline overnight). He files a quality ticket.

**J5. Moderation queue**
> Maria opens the admin app and works through reviews flagged by the AI safety classifier (false-positive rate target <10%, false-negative target <1%).

**J6. Deploy a change**
> Pat opens a PR with a Bicep update + service code change. GitHub Actions runs tests, builds containers, pushes to ACR, runs `bicep what-if`, gets approval, deploys to dev, then promotes to test then prod with manual approval gates. Rollback is one command.

## 4. Functional requirements

> Each requirement is identified as `FR-x.y` and is testable.

### 4.1 Catalog and product detail
- **FR-1.1** The system shall expose a paginated catalog API filterable by category, price range, and rating.
- **FR-1.2** A product detail response shall include core product fields, the last 20 reviews, an AI-generated review summary, and an aggregate sentiment score.
- **FR-1.3** Catalog reads shall hit Redis cache when available; cache TTL is configurable per entity (default 300s for product, 60s for product review feed).
- **FR-1.4** Product images shall be served via CDN with cache-control headers.

### 4.2 Identity and account
- **FR-2.1** Customers shall sign in via Entra External ID using email-password or a federated provider (Google or Microsoft).
- **FR-2.2** Internal users (merchandisers, moderators, platform engineers) shall sign in via the corporate Entra ID tenant with conditional access (MFA required, compliant device for moderators).
- **FR-2.3** All app-to-service authentication shall use Managed Identity. No connection strings or shared keys may be stored in application configuration.
- **FR-2.4** RBAC roles shall follow least privilege: services receive only the data-plane roles required (e.g., `Cosmos DB Built-in Data Contributor` on a specific container, not subscription-level).

### 4.3 Review submission and moderation
- **FR-3.1** Authenticated customers shall submit a review (1–2000 chars, optional image up to 5 MB JPEG/PNG/WebP).
- **FR-3.2** Submitted reviews shall be persisted to a "pending" partition in Cosmos DB before any further processing.
- **FR-3.3** A background worker shall enrich each pending review by calling:
  - Azure AI Language for sentiment + key phrase extraction.
  - Azure AI Content Safety for text and image moderation.
  - Azure AI Vision for image tagging and adult/racy/gory scoring.
- **FR-3.4** Reviews scoring above configurable thresholds shall move to the moderation queue; otherwise they shall be published automatically.
- **FR-3.5** Median end-to-end publish latency (submit → visible on PDP) shall be ≤ 60s for the clean path.
- **FR-3.6** A moderator shall be able to approve, reject, or edit any review through the admin UI; every action shall be audit-logged.

### 4.4 AI shopping assistant
- **FR-4.1** The chat widget shall accept free-text user prompts and return streaming responses.
- **FR-4.2** Responses shall be grounded in the product catalog and a curated FAQ via Retrieval Augmented Generation backed by Azure AI Search with vector indexes.
- **FR-4.3** The assistant shall cite the source products/documents it used and link to them.
- **FR-4.4** A system prompt shall constrain the assistant to retail topics; off-topic and unsafe inputs shall be politely refused.
- **FR-4.5** Per-user rate limiting shall protect the OpenAI quota (default: 20 messages/min, 200/day, configurable).
- **FR-4.6** All chat conversations shall be retained for 30 days for quality review, with PII redaction applied at ingest.

### 4.5 Analytics
- **FR-5.1** Every review submission, view, and chat interaction shall emit a domain event to Azure Event Hubs.
- **FR-5.2** A Stream Analytics job shall compute 1-minute rolling aggregates (reviews/min, avg sentiment, top categories) and write them to a hot store for dashboards.
- **FR-5.3** Raw events shall land in Azure Data Lake Gen2 in Parquet format for batch analytics.
- **FR-5.4** Synapse Analytics shall expose a curated star schema (FactReview, DimProduct, DimCustomer, DimDate) refreshed nightly.
- **FR-5.5** Power BI dashboards shall present:
  - Real-time tile: reviews/min, current avg sentiment.
  - Daily tile: top 10 SKUs by sentiment drop.
  - Weekly tile: emerging complaint clusters from AI categorization.

### 4.6 Administration and operations
- **FR-6.1** All infrastructure shall be deployable from a Bicep template plus a parameter file per environment.
- **FR-6.2** A `bicep what-if` shall run on every PR.
- **FR-6.3** Container images shall be built, scanned (vulnerability + secrets), and pushed to ACR on merge to `main`.
- **FR-6.4** Deployments to test and prod shall require approvals from at least one other reviewer in the environment's GitHub environment protection rules.
- **FR-6.5** Rollback to the prior known-good image shall be a single command or one-click action.

## 5. Non-functional requirements

### 5.1 Performance
- **NFR-P1** Catalog read API: p95 latency ≤ 300ms server-side at the steady-state load.
- **NFR-P2** Review submission: p95 latency ≤ 800ms for the synchronous part (AI enrichment is async).
- **NFR-P3** Chat first-token latency: p95 ≤ 1.5s.

### 5.2 Availability and resilience
- **NFR-A1** Customer-facing API monthly availability target: **99.9%** (≤ 43m downtime/month).
- **NFR-A2** Stateless services shall run with ≥ 2 replicas across ≥ 2 availability zones.
- **NFR-A3** Cosmos DB shall be configured with zone-redundant writes in the primary region and continuous backup.
- **NFR-A4** RTO for a regional outage: ≤ 4h. RPO: ≤ 15 minutes for transactional data, ≤ 1h for analytics.

### 5.3 Scalability
- **NFR-S1** Horizontal Pod Autoscaler shall scale each service between configured min/max based on CPU + custom metric (requests/sec).
- **NFR-S2** Cosmos DB containers shall use autoscale throughput with sane ceilings.
- **NFR-S3** The architecture shall sustain a 10x traffic increase with config changes only — no redesign.

### 5.4 Security
- **NFR-Sec1** Zero secrets in source code or app settings. All secrets live in Azure Key Vault and are referenced via Managed Identity.
- **NFR-Sec2** All data stores shall be reachable only via Private Endpoints in production. Public network access shall be disabled.
- **NFR-Sec3** All HTTPS endpoints shall enforce TLS 1.2+. Public ingress shall pass through Azure Front Door + Application Gateway WAF (OWASP Top 10 ruleset, prevention mode).
- **NFR-Sec4** Microsoft Defender for Cloud shall be enabled at the Defender CSPM and the Defender for Containers / Key Vault / SQL / Storage / App Service plans, depending on what's deployed.
- **NFR-Sec5** Microsoft Sentinel shall ingest activity logs and AKS diagnostic logs.
- **NFR-Sec6** Container images shall fail the build if `Critical` or `High` CVEs are found and not explicitly waived.
- **NFR-Sec7** Identity tokens shall be validated at the API gateway and again at each service.
- **NFR-Sec8** PII shall be classified, encrypted at rest (CMK in prod), and accessible only to roles that need it. Customer chat transcripts shall pass through a PII redaction step before warehouse ingestion.

### 5.5 Observability
- **NFR-O1** Every service shall emit structured logs to Log Analytics with a correlation ID propagated end-to-end.
- **NFR-O2** App Insights shall instrument every service with request, dependency, exception, and custom metric telemetry.
- **NFR-O3** A workbook shall present a "single pane of glass" for golden signals: latency, traffic, errors, saturation per service.
- **NFR-O4** Alerts shall be defined for: p95 latency breach, error rate >1%, queue depth growing, OpenAI throttling, Key Vault access denials, container restart loops.
- **NFR-O5** A monthly cost report shall be auto-generated from Cost Management and posted to Teams/Slack.

### 5.6 Compliance and data protection
- **NFR-C1** Data residency: customer PII shall remain in the primary geo (US).
- **NFR-C2** Data retention: chat transcripts 30 days, audit logs 1 year, analytics aggregates 2 years.
- **NFR-C3** Right-to-erasure: a documented runbook shall delete all data tied to a customer ID across Cosmos, SQL, Blob, and analytics in ≤ 30 days.

### 5.7 Cost
- **NFR-Cost1** Dev environment monthly cost ≤ $150 (auto-shutdown of non-prod resources outside business hours).
- **NFR-Cost2** Each resource shall carry tags: `env`, `costCenter`, `owner`, `dataClassification`.
- **NFR-Cost3** Budgets and action groups shall alert at 50/80/100% of monthly forecast.

## 6. Data requirements

### 6.1 Core entities

| Entity | Store | Partition / index strategy |
|---|---|---|
| `Product` | Cosmos DB (NoSQL) | Partition by `categoryId`. Vector field for embedding-based search via AI Search index. |
| `Review` | Cosmos DB (NoSQL) | Partition by `productId`. TTL not applied. Status enum: pending, approved, rejected. |
| `User` | Azure SQL | Relational; FK from `Order`. PII columns encrypted with Always Encrypted. |
| `Order` | Azure SQL | Stubbed for now. |
| `Image` | Blob Storage | Container `reviews-images`, lifecycle rule to cool tier after 90 days. |
| `ReviewEvent` | Event Hubs → Data Lake Gen2 | Partition by `productCategory`, retained 7 days in EH, indefinite in lake. |
| `Embedding` | AI Search index | Hybrid search: BM25 + vector. |

### 6.2 Data classification

| Classification | Examples | Storage rules |
|---|---|---|
| Public | Product name, description | Any tier, CDN cacheable |
| Internal | Aggregate sentiment scores | Cloud only, RBAC restricted |
| Confidential | Customer email, IP, chat transcripts | Encrypted at rest with CMK, Private Endpoints, audited |
| Restricted | (none in this project) | n/a |

## 7. External dependencies and integrations
- Azure OpenAI Service (GPT-4-class model + an embedding model).
- Azure AI Services multi-service resource (Language, Vision, Content Safety).
- Azure AI Search.
- GitHub (source + Actions).
- Container registry: Azure Container Registry.
- Communications: Microsoft Teams or Slack webhooks for ops alerts.

## 8. Acceptance criteria summary
The system is considered "done" for v1 when:
1. All requirements above pass automated or manual tests in the prod-like test environment.
2. A disaster recovery drill succeeds within stated RTO/RPO.
3. A penetration test (basic OWASP ZAP scan + manual review) yields no Critical or High findings.
4. The full cost of test environment for one billing cycle is within budget.
5. You can rebuild the entire environment in a clean subscription from `git clone` + `azd up` in under 90 minutes.

## 9. Open questions to revisit
- Do we adopt Microsoft Fabric instead of Synapse for the warehouse + BI path? (Plan: start with Synapse since the book covers it; revisit in Phase 5.)
- Do we adopt Dapr on AKS for service-to-service plumbing? (Plan: deferred to v2 unless complexity demands it.)
- Front Door Standard vs Premium? (Plan: Standard for dev/test, Premium in prod for WAF + Private Link origin.)

---
*Next: read `02-Architecture.md` to see how these requirements translate into Azure components.*
