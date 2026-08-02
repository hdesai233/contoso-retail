# Implementation Guide
## Contoso Smart Retail Insights Platform — phased build plan

**Companion to:** `01-Requirements.md`, `02-Architecture.md`
**Style:** Each phase has prerequisites, learning objectives, instructions, validation, and exit criteria. Use Claude Code at every step — see `04-Claude-Code-Playbook.md` for prompt patterns.

---

## Windows conventions used in this guide

All commands below are written for **PowerShell 7+** running in **Windows Terminal**. A few conventions to know:

- **Line continuation** uses the backtick `` ` `` (equivalent of `\` in bash). It must be the *last* character on the line with no trailing whitespace.
- **Variables** are `$name` (not `${name}`). Environment variables are `$env:NAME`.
- **Command substitution** uses the output of a bare command directly: `$issuer = az aks show ... -o tsv` — no `$()` needed.
- **`curl`** in PowerShell is an alias for `Invoke-WebRequest`, which behaves differently. Where I show `curl`, call `curl.exe` explicitly to get the real binary (installed with Git or as part of Windows).
- **`&&` and `||`** work as expected in PowerShell 7+ (but not in the older Windows PowerShell 5.1). Confirm your version with `$PSVersionTable.PSVersion`.
- **Paths** use `\` in native Windows contexts; forward slashes work fine for `az`, `kubectl`, `docker`, Git, and inside container mount paths.
- **`az`, `azd`, `kubectl`, `helm`, `docker`** all work natively on Windows. You don't need WSL — but WSL2 is a reasonable choice if you prefer bash for `kubectl`/`kustomize` workflows. Docker Desktop uses the WSL2 backend by default either way.

### When to consider WSL2
- Multi-command bash pipelines you'd rather not translate.
- Running `make`/`bash` scripts that ship in third-party samples.
- If you plan to also study Linux command-line habits.

Install WSL2 with `wsl --install` (as Administrator), then Ubuntu 22.04 from the Store. Everything below still works from a WSL2 shell — just use the bash forms (`\` continuations, `$(...)`, real `curl`). This guide assumes PowerShell as the default.

### Enable long paths in Git (do this once)
Windows-native Git needs long-path support for some Node/npm and Bicep operations:
```powershell
git config --global core.longpaths true
```

---

## Phase 0 — Foundation

**Goal:** stand up the empty house: subscription, tooling, naming, repo, blank Bicep, blank GitHub Actions, an empty resource group you can deploy into. *No application code yet.*

### Prerequisites
- An Azure subscription with Owner or Contributor + User Access Administrator.
- A GitHub account (free is fine).
- A workstation with: VS Code, Git, Docker Desktop, Node.js LTS, Python 3.11+, .NET 8 SDK.

### Learning objectives
- Subscription, management group, resource group, naming conventions, tagging.
- Bicep basics: modules, parameters, outputs.
- GitHub Actions with **OIDC federated identity** (no service principal secrets).
- `azd` (Azure Developer CLI) as your day-to-day orchestrator.

### Step-by-step

**0.1 Install tools.**

Open an elevated PowerShell 7 window and install everything with `winget`:
```powershell
# Core dev toolchain
winget install --id Microsoft.PowerShell -e             # PowerShell 7+
winget install --id Microsoft.WindowsTerminal -e
winget install --id Git.Git -e
winget install --id GitHub.cli -e
winget install --id Microsoft.VisualStudioCode -e

# Azure toolchain
winget install --id Microsoft.AzureCLI -e
winget install --id Microsoft.Azd -e                    # Azure Developer CLI

# Kubernetes toolchain
winget install --id Docker.DockerDesktop -e             # requires WSL2 backend
winget install --id Kubernetes.kubectl -e
winget install --id Helm.Helm -e

# Language runtimes for the microservices
winget install --id Microsoft.DotNet.SDK.8 -e
winget install --id Python.Python.3.11 -e
winget install --id OpenJS.NodeJS.LTS -e

# Claude Code (via npm, works on Windows)
npm install -g @anthropic-ai/claude-code

# Bicep comes with Azure CLI but keep it current:
az upgrade
az bicep install
az bicep upgrade
```

**Enable Docker Desktop's WSL2 backend** (Docker Desktop → Settings → General → "Use the WSL 2 based engine"). WSL2 will install automatically if it isn't present; if you hit issues, run `wsl --install` from an elevated PowerShell and reboot.

Confirm versions:
```powershell
az version
kubectl version --client
helm version
bicep --version
azd version
dotnet --version
python --version
node --version
docker version
```
If any command isn't found, close and reopen Windows Terminal — the PATH doesn't refresh in the current session after `winget install`.

**0.2 Pick a naming convention and stick to it.**
Adopt the [Microsoft CAF abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations). Pattern:

```
{resourceType}-{workload}-{env}-{region}[-{instance}]
e.g.,  rg-contoso-dev-eus2
       aks-contoso-dev-eus2
       cosmos-contoso-dev-eus2
       kv-contoso-dev-eus2-01
       acrcontosodeveus2          (ACR has no hyphens allowed)
```
Document this in `/docs/naming.md` and have Claude Code enforce it in Bicep modules.

**0.3 Create the repo.**
```powershell
mkdir contoso-retail
cd contoso-retail
git init
# Create the folder structure documented in 02-Architecture.md §3.10
```
Add an initial `CLAUDE.md` at the repo root — see `04-Claude-Code-Playbook.md` for what to put in it.

**0.4 Bootstrap with `azd`.**
```powershell
azd init --template empty
```
Edit `azure.yaml` to reference your future services (start with placeholders).

**0.5 Create the dev subscription and resource group.**
```powershell
az account set --subscription "<your sub id>"
az group create -n rg-contoso-dev-eus2 -l eastus2 `
  --tags env=dev workload=contoso-retail owner="you@example.com" costCenter=learning
```

**0.6 Configure OIDC federated identity for GitHub Actions.**
Have Claude Code generate the App Registration + federated credential + RBAC role assignments. The result: GitHub Actions can `az login` into your subscription with zero secrets.

**0.7 Create your first Bicep skeleton.**
`infra/main.bicep`:
```bicep
targetScope = 'resourceGroup'

@description('Short workload name')
param workload string = 'contoso'

@description('Environment: dev | test | prod')
param env string

@description('Region for resources')
param location string = resourceGroup().location

var tags = {
  workload: workload
  env: env
  managedBy: 'bicep'
}

// Future modules will be wired in here.
output workloadName string = workload
output location string = location
```

`infra/env/dev.bicepparam`:
```bicep
using '../main.bicep'
param workload = 'contoso'
param env = 'dev'
```

Deploy:
```powershell
az deployment group create `
  -g rg-contoso-dev-eus2 `
  -f infra/main.bicep `
  -p infra/env/dev.bicepparam
```

**0.8 Wire the first GitHub Actions workflow.**
`/.github/workflows/ci-infra.yml` should:
- On every PR touching `infra/**`, run `az deployment group what-if` against dev and post the diff as a PR comment.
- On merge to `main`, deploy to dev.
- Require `id-token: write` permission and the federated credential set up in 0.6.

### Validation
```powershell
az group show -n rg-contoso-dev-eus2 -o table
gh workflow run ci-infra.yml
```
Outcome: a successful what-if run reported in the PR.

### Exit criteria
- [ ] Tooling installed, all `--version` checks succeed.
- [ ] Repo on GitHub with the documented folder structure.
- [ ] `CLAUDE.md` written and committed.
- [ ] Bicep `main.bicep` + `dev.bicepparam` deploys an empty `outputs` block successfully.
- [ ] GitHub Actions runs `bicep what-if` on PRs with no secrets stored in GitHub.

---

## Phase 1 — Identity, network, secrets baseline

**Goal:** stand up the platform-wide identity, network, and secret services that everything else will depend on.

### Learning objectives
- Microsoft Entra ID app registrations, Managed Identities, custom RBAC roles.
- VNet design, subnets, NSGs, Private DNS zones.
- Key Vault with RBAC authorization model.
- Defender for Cloud baseline.

### Components to deploy (Bicep modules)
1. `network.bicep` — VNet, 4 subnets (`snet-aks-systempool`, `snet-aks-userpool`, `snet-appgw`, `snet-pe`), NSGs.
2. `keyvault.bicep` — Key Vault with RBAC, soft-delete, purge protection, Private Endpoint, diagnostic settings → LA.
3. `identity.bicep` — User-Assigned Managed Identities for the eight services (placeholders for now), plus role definitions and assignments.
4. `observability.bicep` — Log Analytics workspace, Application Insights, default diagnostic settings.
5. `defender.bicep` — turn on Defender for Cloud foundational CSPM + Defender for KeyVault.

### Step-by-step
1. Implement modules one at a time. Have Claude Code generate each module — see playbook §3 for the exact prompt to use.
2. Wire them into `main.bicep` in this order: observability → network → keyvault → identity → defender.
3. Add Private DNS zones for: `privatelink.vaultcore.azure.net`, `privatelink.documents.azure.com`, `privatelink.database.windows.net`, `privatelink.blob.core.windows.net`, `privatelink.search.windows.net`, `privatelink.openai.azure.com`, `privatelink.azurecr.io`. Link each to the VNet.
4. Confirm Private Endpoint pattern works end-to-end: from a temporary jumpbox in the VNet, resolve and connect to the Key Vault by its private IP only.

### Validation
- `az keyvault show` reveals public network access disabled.
- `Resolve-DnsName <kv-name>.vault.azure.net` from the jumpbox returns a 10.x.x.x address.
- Defender for Cloud dashboard shows secure score baseline.

### Exit criteria
- [ ] Empty VNet with subnets and NSGs deployed.
- [ ] Key Vault accessible only via Private Endpoint; no access policies (RBAC only).
- [ ] LA workspace receiving Activity Logs.
- [ ] Defender CSPM enabled.

---

## Phase 2 — Containers, AKS, the first microservice

**Goal:** prove the full container path: write a service, containerize it, push to ACR, deploy to AKS, ingress works, MI works.

### Learning objectives
- Dockerfile authoring, multi-stage builds, distroless base images.
- ACR with Private Endpoint, customer-managed keys, image scanning.
- AKS with Workload Identity Federation, Application Routing add-on.
- Kustomize overlays, ConfigMaps, Secrets via CSI driver.
- HPA, resource requests/limits.

### Components to deploy
1. `acr.bicep` — Azure Container Registry (Premium), Private Endpoint, customer-managed key from KV.
2. `aks.bicep` — AKS, zone-redundant in prod, Workload Identity enabled, Application Routing add-on, Azure Monitor add-on.
3. The `catalog-svc` microservice — read-only, returns canned data for now.

### Step-by-step

**2.1 Build the cluster.**
Bicep for AKS should include:
- `oidcIssuerProfile.enabled = true`
- `securityProfile.workloadIdentity.enabled = true`
- `networkProfile.networkPlugin = 'azure'`, `networkPluginMode = 'overlay'`, `networkDataplane = 'cilium'` (or kubenet/CNI if you prefer).
- One system node pool (taint `CriticalAddonsOnly=true:NoSchedule`) and one user node pool.
- `ingressProfile.webAppRouting.enabled = true`
- Diagnostic settings to the LA workspace.

Attach ACR to AKS so pulls use the kubelet identity:
```powershell
az aks update -n aks-contoso-dev-eus2 -g rg-contoso-dev-eus2 --attach-acr acrcontosodeveus2
```

**2.2 Write `catalog-svc`.**
Start small: a .NET 8 minimal API or Node Fastify that returns three hard-coded products. Add OpenTelemetry from day one (it's harder to retrofit).

**2.3 Containerize.**
Multi-stage Dockerfile, distroless or Alpine base. No root user. Read-only filesystem. Have Claude Code generate it.

**2.4 Push to ACR.**
```powershell
az acr build -r acrcontosodeveus2 -t catalog-svc:0.1.0 .
```
ACR Tasks builds in the cloud so you don't need local Docker for this — handy since Docker Desktop can be slow to start on Windows.

**2.5 Wire Workload Identity.**
- Create a User-Assigned MI for `catalog-svc` (already in `identity.bicep` Phase 1).
- Federate it to the cluster's OIDC issuer for a specific namespace + ServiceAccount:
```powershell
$issuer = az aks show -g rg-contoso-dev-eus2 -n aks-contoso-dev-eus2 `
  --query oidcIssuerProfile.issuerUrl -o tsv

az identity federated-credential create `
  --name catalog-svc-fc `
  --identity-name mi-catalog-svc-dev `
  --resource-group rg-contoso-dev-eus2 `
  --issuer $issuer `
  --subject system:serviceaccount:catalog:catalog-svc
```
- The Kubernetes ServiceAccount needs the `azure.workload.identity/client-id` annotation; the Pod template needs the `azure.workload.identity/use: "true"` label.

**2.6 Deploy with Kustomize.**
`k8s/base/catalog-svc/`: `deployment.yaml`, `service.yaml`, `serviceaccount.yaml`, `kustomization.yaml`, plus an `ingress.yaml` using the App Routing add-on's `webapprouting.kubernetes.azure.com` ingress class.

```powershell
kubectl apply -k k8s/overlays/dev
```

**2.7 Validate the round-trip.**
```powershell
$ingressIp = kubectl get ingress -n catalog catalog-svc `
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Use curl.exe (not the PowerShell alias) so headers behave as expected
curl.exe -H "Host: catalog.dev.contoso.example" "http://$ingressIp/api/products"
```
> Or use PowerShell-native: `Invoke-RestMethod -Uri "http://$ingressIp/api/products" -Headers @{ Host = "catalog.dev.contoso.example" }`

**2.8 Add HPA.**
Scale on CPU `targetAverageUtilization: 70`, min 2, max 5.

### Exit criteria
- [ ] AKS cluster healthy, two services running (kube-system + catalog).
- [ ] Image scan on push reports no Critical or High CVEs.
- [ ] `catalog-svc` reachable via the ingress IP and returns canned products.
- [ ] No connection strings or secrets in `deployment.yaml`.
- [ ] App Insights shows traces with correlation IDs.

---

## Phase 3 — Data plane

**Goal:** replace canned data with real persistence. Add Cosmos, SQL, Blob, Redis. All accessed via Managed Identity and Private Endpoints.

### Learning objectives
- Cosmos partition design and RU/s tuning.
- AAD authentication to Azure SQL.
- SAS token issuance from a service.
- Cache-aside pattern with Redis.

### Components to deploy
1. `cosmos.bicep` — account, database, three containers (`products`, `reviews`, `chat-history`), autoscale, continuous backup, PE.
2. `sql.bicep` — server + DB, Entra-only auth, Always Encrypted setup hooks, PE, auditing to LA.
3. `storage.bicep` — StorageV2 account with containers `reviews-images-pending`, `reviews-images-approved`, `public-thumbnails`; lifecycle policy; PE.
4. `redis.bicep` — Standard tier in dev (Premium with VNet injection in prod).
5. `service-bus.bicep` — namespace, queue `review-moderation-jobs`, topic `review-status-changed`.

### Step-by-step

**3.1 Seed Cosmos with a real catalog.**
Write a small script (`scripts/seed-catalog.ts`) that loads 50 products from `data/products.json` into Cosmos. Run it once from your machine via Entra auth (you may need to temporarily grant your user the Data Contributor role on the container, then revoke).

**3.2 Update `catalog-svc` to read from Cosmos.**
- Use the official SDK with `DefaultAzureCredential` (no keys).
- Implement cache-aside with Redis: try Redis, miss → Cosmos → set in Redis with TTL 300s.
- Assign the service's MI the `Cosmos DB Built-in Data Contributor` role scoped to the `products` container.

**3.3 Build `review-svc`.**
- POST `/api/reviews` validates JWT, persists to Cosmos `reviews` container with status `pending`, returns 202.
- Issues a SAS for image upload if requested.
- Publishes an event to Service Bus `review-moderation-jobs`.

**3.4 Configure Service Bus auth.**
- The MI for `review-svc` gets `Azure Service Bus Data Sender` on the queue.
- The MI for `moderation-worker` gets `Azure Service Bus Data Receiver`.

**3.5 Validate end-to-end.**
- Submit a review via `curl` with a customer token.
- Confirm document appears in Cosmos with status `pending`.
- Confirm message lands in Service Bus.

### Exit criteria
- [ ] `catalog-svc` reads catalog from Cosmos via MI.
- [ ] `review-svc` accepts a review, persists it, and publishes a queue message.
- [ ] Redis cache hit rate observable in App Insights.
- [ ] No connection strings in code or k8s manifests.

---

## Phase 4 — AI plane

**Goal:** make the platform actually intelligent. Deploy OpenAI, AI Search, AI Services. Build the moderation worker and the shopping assistant.

### Learning objectives
- Azure OpenAI deployments, model selection, PTU vs PAYG.
- Embeddings + vector search in AI Search.
- Hybrid retrieval, semantic ranking.
- RAG pattern, prompt construction, citation.
- AI Content Safety thresholds.
- KEDA event-driven autoscaling.

### Components to deploy
1. `openai.bicep` — Azure OpenAI resource, deployments for `gpt-4o` (or current best) and `text-embedding-3-large`, PE, MI access.
2. `ai-search.bicep` — Standard tier, semantic ranker enabled, PE, MI access.
3. `ai-services.bicep` — multi-service Cognitive Services account (Language, Vision, Content Safety), PE.
4. `moderation-worker` Deployment with **KEDA** ScaledObject keyed off Service Bus queue depth.
5. `assistant-svc` Deployment.

### Step-by-step

**4.1 Deploy AI resources and validate PE access.**
Pop a debug pod into the cluster:
```powershell
kubectl run debug --image=mcr.microsoft.com/azure-cli -it --rm -- bash
```
Then, inside the container's bash shell:
```bash
az login --identity
az cognitiveservices account list-keys ...   # should work via MI
```
(The pod runs Linux, so the shell inside is bash regardless of your host OS.)

**4.2 Build the moderation worker.**
Pseudocode:
```python
async for message in service_bus_receiver:
    review = json.loads(message.body)
    sentiment = await language.analyze_sentiment(review["text"])
    safety = await content_safety.analyze_text(review["text"])
    if review.get("imageBlob"):
        image_safety = await content_safety.analyze_image(blob_bytes)
        vision = await vision.analyze(blob_bytes, features=["tags","read"])
    new_status = "approved" if max(severities) < threshold else "needs-review"
    await cosmos.patch(review["id"], partition=review["productId"], status=new_status, ai_scores=...)
    await event_hub.send({"type":"review.scored", ...})
    await message.complete()
```

**4.3 Add KEDA ScaledObject.**
Trigger: `azure-servicebus`. Min 0, max 10 replicas. Use Workload Identity for KEDA auth.

**4.4 Build the assistant service (RAG).**
Indexer pulls products from Cosmos → AI Search `products-index` with vector fields generated by an indexer skillset calling the embedding model.

Chat orchestration in `assistant-svc`:
1. Embed user query.
2. Hybrid search in AI Search: BM25 + vector + semantic re-ranker → top-K.
3. Construct prompt: system instructions + retrieved snippets + user message.
4. Stream completion from OpenAI back to client.
5. Append citations.
6. Save conversation turn to `chat-history` Cosmos container.

**4.5 Apply rate limits at APIM.**
Per-subscription policy enforcing 20 calls/min/user.

**4.6 Verify content safety end-to-end.**
Submit a deliberately toxic review and a benign one; confirm correct routing.

### Exit criteria
- [ ] Submitting a review triggers AI enrichment; status flips correctly.
- [ ] Chat widget returns grounded answers with citations.
- [ ] Rate limit kicks in when exceeded.
- [ ] KEDA scales `moderation-worker` from 0 to N under burst load.

---

## Phase 5 — Analytics plane

**Goal:** turn the event stream into dashboards.

### Learning objectives
- Event Hubs partitioning and Capture.
- Stream Analytics queries (windowed aggregations).
- ADLS Gen2 lakehouse layout (bronze/silver/gold).
- Synapse serverless SQL pool, Spark pool basics.
- Power BI workspace, DirectQuery vs Import, real-time tiles.
- Microsoft Purview classification.

### Components to deploy
1. `eventhubs.bicep` — namespace, `domain-events` hub, Capture to ADLS.
2. `storage-adls.bicep` — separate ADLS Gen2 account, containers `bronze`, `silver`, `gold`.
3. `stream-analytics.bicep` — job with EH input, Cosmos `realtime-metrics` output, PowerBI streaming output.
4. `synapse.bicep` — workspace, serverless pool, optional Spark pool.
5. `purview.bicep` — account; register Cosmos, SQL, ADLS, Synapse as data sources.

### Step-by-step

**5.1 Publish events.**
Update `review-svc` and the worker to publish to Event Hubs. Use the SDK with MI. Standardize a `CloudEvents`-compatible envelope.

**5.2 Stream Analytics query.**
```sql
SELECT
  productCategory,
  System.Timestamp() AS windowEnd,
  COUNT(*) AS reviewCount,
  AVG(sentimentScore) AS avgSentiment
INTO [cosmos-realtime]
FROM [eventhub-domain]
WHERE eventType = 'review.scored'
GROUP BY productCategory, TumblingWindow(minute, 1)
```

**5.3 Lakehouse build.**
Capture lands raw events as Avro in `bronze/`. A Synapse Spark notebook converts to Parquet under `silver/` partitioned by date. Another notebook builds the `gold/` star schema.

**5.4 Power BI.**
- Connect to Synapse serverless via DirectQuery for the warehouse tiles.
- Add the Stream Analytics streaming dataset for the live tile.
- Publish to a workspace and configure row-level security.

**5.5 Purview classification.**
Run scans; confirm PII columns (e.g., `email` in SQL) are auto-classified.

### Exit criteria
- [ ] Live tile updates within 60 seconds of a review.
- [ ] Synapse query against `gold/` returns daily aggregates.
- [ ] Purview shows classifications across all four data sources.

---

## Phase 6 — Hardening, observability, cost, DR

**Goal:** make it prod-shaped.

### Components/configurations
1. **Front Door + WAF** in front of everything; lock APIM ingress to Front Door.
2. **APIM** in front of public APIs with policies: JWT validation, rate limit, request body validation, correlation ID injection.
3. **Defender plans**: Containers, Key Vault, SQL, Storage, App Service, Resource Manager.
4. **Microsoft Sentinel** with starter analytics rules.
5. **Network hardening**: NSGs reviewed, Private Endpoints everywhere, public access disabled on every data store.
6. **Observability**: Workbooks, alerts, dashboards.
7. **Cost**: budgets and action groups; auto-shutdown of dev outside business hours via a Logic App.
8. **DR drill**: practice the runbook.

### Sample alert set (Bicep / KQL)
- p95 latency > 800ms over 10m on any service.
- Error rate > 1% over 5m on any service.
- Service Bus queue depth > 1000 for 5m.
- OpenAI 429 responses > 5 in 5m.
- Key Vault access denied count > 0.
- Container restart count > 3 in 10m.

### Exit criteria
- [ ] All data services have public network disabled.
- [ ] OWASP ZAP scan passes (no Critical/High).
- [ ] Secure score ≥ target in Defender for Cloud.
- [ ] DR drill completes within RTO.
- [ ] Monthly cost report posted automatically.

---

## Appendix A — Decision log template

Keep a `docs/decisions/` folder with one ADR per significant choice. Format:
```
# ADR-007: Use Bicep over Terraform
Status: Accepted
Date: YYYY-MM-DD
Context: ...
Decision: ...
Consequences: ...
```

## Appendix B — Runbooks to write
- `runbooks/dr.md` — failover steps.
- `runbooks/key-rotation.md` — rotate KV-managed secrets/keys.
- `runbooks/incident-template.md` — standard incident response.
- `runbooks/customer-deletion.md` — right-to-erasure.

## Appendix C — Stretch goals after v1
- Replace Synapse with Microsoft Fabric (OneLake + Direct Lake).
- Swap App Routing add-on for AGIC.
- Add Dapr for service-to-service plumbing.
- Add Customer Lockbox in prod.
- Multi-region active-active with Cosmos multi-region writes and Front Door routing.
- Replace your own AI orchestration with **Azure AI Foundry** for evaluation, prompt flow, and observability of the AI pipeline.

---

*Next: read `04-Claude-Code-Playbook.md` for how to drive all of this with Claude Code.*
