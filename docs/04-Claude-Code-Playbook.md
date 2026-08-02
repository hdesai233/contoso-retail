# Claude Code Playbook
## How to use Claude Code as your Azure pair-programmer on this project

**Companion to:** the other three documents.
**Audience:** you, sitting at a terminal with `claude` available.

This playbook covers (1) how to set up Claude Code so it's actually useful for an Azure project, (2) the `CLAUDE.md` content that gives it durable context, (3) reusable prompt patterns, (4) phase-specific prompts you can paste verbatim, and (5) common pitfalls.

---

## 1. One-time setup (Windows)

Claude Code runs natively on Windows. All commands below assume **PowerShell 7+** in Windows Terminal.

```powershell
# Install (you've probably already done this in Phase 0)
npm install -g @anthropic-ai/claude-code

# Verify
claude --version

# Authenticate — follows prompts on first run
claude
```

Open Claude Code from inside your project repo:
```powershell
cd contoso-retail
claude
```

Claude Code reads `CLAUDE.md` at the repo root and any `CLAUDE.md` in subdirectories it walks into. This is where you give it durable, project-specific instructions so you don't repeat yourself every session.

### Windows-specific tips for Claude Code
- **File paths.** When you paste Windows paths into Claude, forward slashes work fine (`infra/modules/aks.bicep`); avoid backslashes because they can be misread as escape characters.
- **Long paths.** If Claude Code (or its tools) complain about paths over 260 chars, ensure Git long-path support is on: `git config --global core.longpaths true`, and enable Windows long paths (`New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force`).
- **Shell that Claude runs commands in.** Claude Code uses your default shell. If you're on PowerShell, ask it to write PowerShell one-liners (or say "use bash" if you'd rather it write for WSL). Being explicit avoids getting Linux-only tricks like `$(...)` command substitution.
- **WSL2 alternative.** If you'd rather run Claude Code from Ubuntu inside WSL2, install Node in WSL (`sudo apt install nodejs npm`) then `npm install -g @anthropic-ai/claude-code`. The rest of this playbook still applies; you'll get bash-native commands from Claude by default.

## 2. The `CLAUDE.md` you should commit at the repo root

Drop this into `CLAUDE.md` and tweak as the project evolves:

```markdown
# CLAUDE.md — Contoso Retail Insights Platform

## Project overview
An Azure-native, microservices-on-AKS retail platform with AI moderation, an
AI shopping assistant, and an analytics pipeline. Build follows the phases in
`docs/03-Implementation-Guide.md`. Architecture lives in `docs/02-Architecture.md`.

## Tech stack
- IaC: **Bicep** (no Terraform).
- Cluster: **AKS** with the Application Routing add-on and Workload Identity.
- Languages: .NET 8 for catalog-svc, review-svc, admin-bff. Python 3.11 for
  assistant-svc and moderation-worker. Node/Fastify for notification-svc and
  analytics-collector. React + Vite + TypeScript for web-frontend.
- Data: Cosmos DB NoSQL, Azure SQL, Blob Storage, Redis. Service Bus and
  Event Hubs for messaging.
- AI: Azure OpenAI + Azure AI Search + Azure AI Services (Language, Vision,
  Content Safety).
- Observability: Azure Monitor, App Insights, Log Analytics with OpenTelemetry.

## House rules (always follow)
1. **No secrets in code or config.** Every credential is fetched from Key Vault
   via Managed Identity. Use `DefaultAzureCredential` in app code. In Bicep,
   never output secrets; pass them as Key Vault references.
2. **No public network access on data services in `test` and `prod` overlays.**
   Private Endpoints only. The `dev` overlay may keep public access for
   convenience but explicitly notes this with a comment.
3. **Bicep style:** modules under `infra/modules/`. Use `param` decorators
   (`@description`, `@allowed`, `@minLength`). Apply the tags object from
   `main.bicep` to every resource. Use the CAF abbreviation prefix in names.
4. **K8s style:** Kustomize, not Helm. Base in `k8s/base/`, env overlays in
   `k8s/overlays/{dev,test,prod}/`. Always set resource requests/limits, a
   readiness probe, a liveness probe, and `runAsNonRoot: true`.
5. **Tests first** for any business logic. xUnit for .NET, pytest for Python,
   Vitest for TS.
6. **Telemetry:** every service starts with OpenTelemetry wired to App Insights;
   propagate W3C `traceparent`. Log structured JSON; never `Console.WriteLine`.
7. **PR hygiene:** small PRs. Update `docs/decisions/` when a non-trivial
   choice is made (ADR format).

## Naming convention
`{abbr}-{workload}-{env}-{region}[-{instance}]` per CAF. Workload = `contoso`.
Examples: `aks-contoso-dev-eus2`, `cosmos-contoso-dev-eus2`. ACR has no
hyphens: `acrcontosodeveus2`.

## How I want you to work
- Before making non-trivial changes, surface a short plan with the tradeoffs.
- Prefer adding a TODO comment over making up an API. If something is unclear,
  ask me one focused question rather than guessing.
- When you generate code, run the build/tests locally if possible and report
  the result.
- When you generate Bicep, run `az bicep build` and `az deployment group what-if`
  in the dev resource group if I've left credentials available.
- Cite Microsoft Learn URLs in your responses when they're load-bearing for a
  decision; I will follow up on them.
```

## 3. Prompt patterns that work well for Azure work

### 3.1 Scaffolding pattern
> "Scaffold a new service `<name>` in `apps/<name>` following the conventions in `CLAUDE.md` and the architecture doc. It should be a `<.NET 8 minimal API | Python FastAPI | Node Fastify>` exposing `<endpoints>`. Include a multi-stage Dockerfile, a Kustomize base under `k8s/base/<name>/`, OpenTelemetry wired to App Insights, a healthz endpoint, and a Bicep module under `infra/modules/<name>-identity.bicep` that creates the User-Assigned MI and the federated credential for namespace `<ns>` and ServiceAccount `<sa>`. Don't add any secrets to manifests."

### 3.2 Bicep authoring pattern
> "Write a Bicep module `infra/modules/<name>.bicep` for `<resource>` that:
> - Uses Private Endpoint in `<subnet name>`.
> - Disables public network access.
> - Sends diagnostic settings to the Log Analytics workspace `<la name>` for these categories: `<list>`.
> - Receives a `tags` param and applies it.
> - Outputs `<list of outputs>`.
> Follow the existing modules in `infra/modules/` for style. Validate with `az bicep build`."

### 3.3 KQL pattern
> "Write a KQL query against the Application Insights logs that shows the p50/p95/p99 latency by `cloud_RoleName` for HTTP requests in the last 1 hour, excluding requests with `resultCode == 0`. Format as a `let` chain so I can paste it into a Workbook."

### 3.4 Explain-an-error pattern (best for debugging Azure)
> "I'm getting this error: `<paste>`. Context: I just deployed `<module>` in environment `<env>`. Tell me the most likely root causes ranked by probability, the diagnostic commands to confirm each, and the fix."

### 3.5 Review pattern
> "Review `infra/modules/aks.bicep` for security and reliability issues. Use the Azure Well-Architected Framework as your checklist. Output a markdown table with finding | severity | fix."

### 3.6 Document-with-citations pattern
> "I want to enable Customer-Managed Keys on the ACR I deployed. Walk me through the steps as a numbered list, with the exact `az` commands and a Bicep snippet of what changes. Cite the Microsoft Learn pages you used."

## 4. Phase-by-phase prompts you can paste

### Phase 0
- *"Generate the GitHub Actions workflow that authenticates via OIDC federated identity (no secrets) and runs `az deployment group what-if` on every PR that touches `infra/**`. Post the diff as a PR comment. Also generate the `az ad app federated-credential` commands I need to run once to set up the federation, parameterized by repo `${owner}/${repo}` and branch."*

- *"Generate `docs/naming.md` documenting the CAF-style naming convention I've adopted and listing the exact names this project will use for each resource type, separated by environment."*

### Phase 1
- *"Generate `infra/modules/network.bicep` for a VNet `10.20.0.0/16` with subnets `snet-aks-systempool` (10.20.0.0/22), `snet-aks-userpool` (10.20.4.0/22), `snet-appgw` (10.20.8.0/24), `snet-pe` (10.20.9.0/24), `snet-apim` (10.20.10.0/24). Add baseline NSGs to each. Output the subnet IDs."*

- *"Generate `infra/modules/keyvault.bicep` for a Premium Key Vault with RBAC auth, soft-delete, purge protection, disabled public network access, a Private Endpoint in `snet-pe`, and diagnostic settings for `AuditEvent` and `AllMetrics` to LA workspace `<id>`. Accept `tags`, `keyVaultName`, `subnetId`, `privateDnsZoneId`, `laWorkspaceId` as params. Output `vaultUri`."*

- *"Generate Private DNS zones for: vaultcore, documents, database.windows, blob.core, search.windows, openai, azurecr, file.core, table.core, queue.core. Link them to the VNet. Output a `privateDnsZoneIds` object."*

### Phase 2
- *"Generate `infra/modules/aks.bicep` with: Workload Identity + OIDC issuer enabled, Application Routing add-on, Azure Monitor add-on, Defender add-on, Azure CNI overlay, Cilium dataplane, one system node pool (taint `CriticalAddonsOnly`), one user node pool (Standard_D4s_v5, 2 nodes, autoscale 2-5). Wire diagnostic settings to LA."*

- *"Scaffold `apps/catalog-svc` as a .NET 8 minimal API with three endpoints: `GET /api/products`, `GET /api/products/{id}`, `GET /healthz`. Use the Microsoft.Azure.Cosmos SDK with `DefaultAzureCredential` (no keys). Add the OpenTelemetry packages and wire the App Insights exporter from `APPLICATIONINSIGHTS_CONNECTION_STRING` env var. For now, fall back to in-memory canned products if Cosmos config is absent. Include unit tests."*

- *"Write the Kustomize base for `catalog-svc` and a `dev` overlay that:
> - Annotates the SA with the MI client ID.
> - Labels the Pod for Azure Workload Identity.
> - Sets resource requests/limits.
> - Sets `runAsNonRoot: true` and `readOnlyRootFilesystem: true`.
> - Exposes an Ingress via the Application Routing add-on.
> - Mounts a configmap with the Cosmos endpoint URL.
> No secrets."*

### Phase 3
- *"Generate `infra/modules/cosmos.bicep` for an Azure Cosmos DB for NoSQL account with: continuous backup, public network access disabled, Private Endpoint in `snet-pe`, a database `contoso-retail`, three containers (`products` PK `/categoryId`, `reviews` PK `/productId`, `chat-history` PK `/userId` with 30-day TTL). Use autoscale 1k-4k RU per container. Output the account endpoint."*

- *"Add to `cosmos.bicep` data-plane role assignments granting the `mi-catalog-svc` MI the `Cosmos DB Built-in Data Reader` role scoped to the `products` container only."*

- *"Update `catalog-svc` so it reads from Cosmos with cache-aside on Redis. Use `DefaultAzureCredential` for both. The Redis password is in Key Vault, but prefer using Entra auth for Redis Enterprise; for Standard Redis use Key Vault. Show me both options and pick the simpler one for dev."*

### Phase 4
- *"Build the `moderation-worker` as a Python `azure-servicebus` consumer. For each message:
> 1. Pull review from Cosmos.
> 2. Call AI Language `analyze_sentiment` and `extract_key_phrases`.
> 3. Call AI Content Safety on the text; if image present, call Vision tags + Content Safety on the image bytes.
> 4. If max severity < `MODERATION_THRESHOLD` (env var), set status to `approved`; else `needs-review`.
> 5. PATCH the Cosmos doc.
> 6. Publish `review.scored` to Event Hubs.
> Use `DefaultAzureCredential` everywhere. Add structured logging with correlation ID from the message properties. Add a KEDA `ScaledObject` triggering on queue depth, min 0 max 10."*

- *"Build `assistant-svc` as a FastAPI app with `POST /chat` that streams Server-Sent Events. Implementation:
> 1. Embed user query with `text-embedding-3-large` via Azure OpenAI.
> 2. Hybrid query Azure AI Search `products-index` (vector + BM25 + semantic re-ranker), top 5.
> 3. Compose prompt with strict system message confining the assistant to retail.
> 4. Call `gpt-4o` deployment with streaming; stream back to the client.
> 5. Append a citations object.
> 6. Persist the turn to Cosmos `chat-history`. Use MI auth. No keys."*

### Phase 5
- *"Generate the Stream Analytics query that consumes from `eventhub-domain`, filters events where `eventType = 'review.scored'`, computes 1-minute tumbling aggregates of count and avg sentiment grouped by `productCategory`, and writes to a Cosmos `realtime-metrics` container and a Power BI streaming dataset. Provide the Bicep for the SA job too."*

- *"Write a Synapse Spark notebook (PySpark) that reads the Avro files Capture is dropping at `abfss://bronze@<adls>.dfs.core.windows.net/eventhub-domain/...`, parses the CloudEvents envelope, flattens to a table, and writes Parquet to `abfss://silver@.../reviews/` partitioned by `ingest_date`. Idempotent (use `mode='overwrite'` with partition overwrite mode `dynamic`)."*

### Phase 6
- *"Generate `infra/modules/apim.bicep` for an APIM Standard v2 instance in `snet-apim` with: managed identity, JWT validation policy template (validating tokens from External ID), rate-limit-by-key policy (20 calls/min per user), correlation header injection. Apply to a sample `catalog-api` operation."*

- *"Write KQL Sentinel analytics rules for: (1) impossible-travel sign-ins for users with the `Platform-Admin` role, (2) > 10 Key Vault access denials in 10 minutes from a single principal, (3) container privilege escalation events. Output as Bicep `analyticsRules` resources."*

## 5. Things Claude Code is *especially* good at on Azure projects
- Drafting Bicep modules and explaining their parameters.
- Turning a portal screenshot or `az ... --debug` output into a Bicep snippet.
- Writing KQL queries against App Insights/Log Analytics from a plain-English description.
- Generating Dockerfiles that respect distroless/non-root constraints.
- Reviewing IAM role assignments for over-privilege.
- Translating "I want to do X with Azure SDK" into idiomatic SDK code with `DefaultAzureCredential`.
- Writing GitHub Actions with OIDC federation correctly the first time.
- Producing ADRs and runbooks in your house style.

## 6. Things to do *yourself*, not in Claude Code
- The first `az login` and subscription selection.
- Approving anything that costs real money beyond a dev tier (e.g., creating PTU OpenAI capacity).
- Reviewing the diff of any IAM/RBAC change before applying it.
- Final review of any prompt template that constrains the AI shopping assistant — wording matters a lot.

## 7. Recovering when Claude Code gets it wrong
- "Show me your plan" — make it state intent before changing files.
- "Stop, revert" — back out the last set of changes via `git restore`.
- "What's the alternative approach if we instead avoid X?" — forces it to surface tradeoffs.
- If it's hallucinating an API: paste the actual `az --help` output or SDK docs URL.

## 8. Suggested daily rhythm
1. **Morning**: open Claude Code, summarize where you left off, ask it to propose today's smallest valuable change.
2. Implement that change in a branch with Claude doing the boilerplate, you doing the review.
3. Run tests, run `bicep what-if`, commit.
4. End of day: ask Claude to write a short note in `docs/journal.md` summarizing what changed and what's next. Future-you will thank past-you.

---

*That's it. Open Claude Code in the repo, paste prompts from §4 in order, and you're building a real Azure platform tomorrow.*
