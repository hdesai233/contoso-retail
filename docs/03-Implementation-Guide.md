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
Write this down formally in step 0.7 below, then have Claude Code enforce it in every Bicep module going forward.

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

**0.5 Check which regions your subscription actually allows.**
Sandbox, student, and CSP-managed subscriptions frequently carry an **"Allowed resource deployment regions"** policy set at the tenant or management-group level, restricting you to a handful of regions regardless of what your naming convention assumes. Check *before* you pick a region and bake it into resource names:
```powershell
az policy assignment list --query "[?displayName=='Allowed resource deployment regions']" -o table
# If one exists, see its allowed list:
az policy assignment show --name <name-from-above> --query "parameters.listOfAllowedLocations.value" -o tsv
```
This project hit exactly this on its dev subscription — `eastus2` was blocked, `eastus` wasn't. Rather than discover it mid-deployment (which is what happened — `az deployment group what-if` failed with `RequestDisallowedByAzure` on every resource), check first. If your region is restricted, record the decision as an ADR (see `docs/decisions/ADR-001-dev-region-eastus.md` for this project's own example) and update `docs/naming.md` and `infra/env/*.bicepparam` accordingly before writing any modules.

**0.6 Create the dev subscription and resource group.**
```powershell
az account set --subscription "<your sub id>"
az group create -n rg-contoso-dev-eus2 -l eastus2 `
  --tags env=dev workload=contoso-retail owner="you@example.com" costCenter=learning
```
> The resource group's own name/location aren't restricted by the region policy above (only resources deployed *into* it are) — so `rg-contoso-dev-eus2` and `-l eastus2` are fine here even if your region turned out to be `eastus` per 0.5. Just make sure `infra/env/dev.bicepparam` sets `location`/`regionAbbr` to whatever 0.5 found allowed, not necessarily `eastus2`.

**0.7 Document the naming convention.**
Before writing any Bicep, decide and write down every exact resource name you'll use — cheaper to fix a name on paper than after three modules depend on it.

> **Claude Code prompt:**
> *"Generate `docs/naming.md` documenting the CAF-style naming convention I've adopted and listing the exact names this project will use for each resource type, separated by environment."*

**0.8 Configure OIDC federated identity for GitHub Actions.**
Have Claude Code generate the App Registration + federated credential + RBAC role assignments. The result: GitHub Actions can `az login` into your subscription with zero secrets.

**0.9 Create your first Bicep skeleton.**
`infra/main.bicep`:
```bicep
targetScope = 'resourceGroup'

@description('Short workload name')
param workload string = 'contoso'

@description('Environment: dev | test | prod')
param env string

@description('Region for resources')
param location string = resourceGroup().location

@description('CAF region abbreviation used in resource names — must match `location`. See 0.5: this can differ per environment if your subscription restricts regions.')
param regionAbbr string = 'eus2'

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
param location = 'eastus2'    // or whatever 0.5 found your subscription allows
param regionAbbr = 'eus2'     // must match location
```

Validate, preview, then deploy — this is the pattern to use for every deployment for the rest of the project, not just this one:
```powershell
az bicep build --file infra/main.bicep

az deployment group what-if `
  -g rg-contoso-dev-eus2 `
  -f infra/main.bicep `
  -p infra/env/dev.bicepparam

az deployment group create `
  -g rg-contoso-dev-eus2 `
  -f infra/main.bicep `
  -p infra/env/dev.bicepparam
```
`what-if` costs nothing and catches most mistakes (wrong param, disallowed region, naming collision) before Azure actually tries to create anything — always run it first, especially on a shared or budget-constrained subscription.

> **Note if you're driving this through Claude Code in a Git Bash/MSYS shell on Windows (not native PowerShell):** MSYS auto-converts arguments that look like absolute Unix paths, so any `--parameters` value starting with `/subscriptions/...` (a resource ID) gets silently mangled into something like `C:/Program Files/Git/subscriptions/...`. `what-if` will still report `"status": "Succeeded"` with the corrupted value baked into the payload — it doesn't validate that the ID is real, so this fails silently rather than loudly. Fix: prefix the command with `export MSYS_NO_PATHCONV=1`, or run it from native PowerShell instead. Always spot-check resource-ID parameters in the `what-if` JSON output before trusting a green result.

**0.10 Wire the first GitHub Actions workflow.**
`/.github/workflows/ci-infra.yml` should:
- On every PR touching `infra/**`, run `az deployment group what-if` against dev and post the diff as a PR comment.
- On merge to `main`, deploy to dev.
- Require `id-token: write` permission and the federated credential set up in 0.8.

> **Claude Code prompt:**
> *"Generate the GitHub Actions workflow that authenticates via OIDC federated identity (no secrets) and runs `az deployment group what-if` on every PR that touches `infra/**`. Post the diff as a PR comment. Also generate the `az ad app federated-credential` commands I need to run once to set up the federation, parameterized by repo `${owner}/${repo}` and branch."*

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
1. `network.bicep` — VNet, 4 subnets (`snet-appgw`, `snet-pe`, `snet-apim`, `snet-aca`), NSGs, plus the Private DNS zone(s) each subsequent module's Private Endpoint needs (see step 3 below). `snet-aca` hosts the Phase 2 Container Apps environment — see ADR-002; it's sized `/23` and deliberately **not** delegated, since the Consumption-only environment type requires exactly that.
2. `keyvault.bicep` — Key Vault with RBAC, soft-delete, purge protection, Private Endpoint, diagnostic settings → LA.
3. `identity.bicep` — User-Assigned Managed Identities for the eight services (placeholders for now). Role *assignments* are **not** created here — see step 4.
4. `observability.bicep` — Log Analytics workspace, workspace-based Application Insights, subscription Activity Log routed to the workspace.
5. `defender.bicep` — turn on Defender for Cloud foundational CSPM + Defender for Key Vault. **Subscription-scoped** (`targetScope = 'subscription'`), not resource-group-scoped — `Microsoft.Security/pricings` has no `location`/`tags` property and applies to the whole subscription. If dev/test/prod share one subscription, deploy this module once total, not once per environment; calling it repeatedly is harmless (idempotent) but redundant. Defender for Key Vault at `Standard` tier is billed per vault — check this is acceptable before deploying on a cost-constrained subscription.

### Step-by-step
1. Implement modules one at a time.

   > **Claude Code prompt — network.bicep:**
   > *"Generate `infra/modules/network.bicep` for a VNet `10.20.0.0/16` with subnets `snet-appgw` (10.20.8.0/24), `snet-pe` (10.20.9.0/24), `snet-apim` (10.20.10.0/24), `snet-aca` (10.20.16.0/23, not delegated — Consumption-only Container Apps environment). Add baseline NSGs to each. Output the subnet IDs."*

   > **Claude Code prompt — keyvault.bicep:**
   > *"Generate `infra/modules/keyvault.bicep` for a Premium Key Vault with RBAC auth, soft-delete, purge protection, disabled public network access, a Private Endpoint in `snet-pe`, and diagnostic settings for `AuditEvent` and `AllMetrics` to LA workspace `<id>`. Accept `tags`, `keyVaultName`, `subnetId`, `privateDnsZoneId`, `laWorkspaceId` as params. Output `vaultUri`."*

   > **Claude Code prompt — observability, identity, defender:**
   > *"Can you generate observability, identity and defender bicep files?"* — vague on purpose; a competent assistant should already know these three from the components list above and pull the spec from `docs/02-Architecture.md` and this guide rather than needing everything spelled out again. If it doesn't, that's a signal your `CLAUDE.md` isn't pointing it at the right docs.

2. Add Private DNS zones **incrementally, one per module, not all upfront.** Each module that provisions a Private Endpoint also provisions the matching `privatelink.*` zone and links it to the VNet — e.g. `network.bicep` creates `privatelink.vaultcore.azure.net` because `keyvault.bicep`'s Private Endpoint needs it; `cosmos.bicep` (Phase 3) will create `privatelink.documents.azure.net` when it needs it, and so on. This was a deliberate change from an earlier draft of this guide, which had all seven zones (`vaultcore`, `documents`, `database.windows`, `blob.core`, `search.windows`, `openai`, `azurecr`) created upfront in Phase 1 — that meant several zones sitting unused for phases, with no resource yet to link them to. Creating each zone next to the resource that needs it keeps the two from drifting apart.
3. Wire modules into `main.bicep` in this order: observability → network → keyvault → identity → defender. `defender` additionally needs `scope: subscription()` on its module declaration, since `main.bicep` itself is resource-group-scoped.
4. **Deploy each module as you finish it** — don't wait until all five are written. For each:
   ```powershell
   az bicep build --file infra/modules/<module>.bicep

   az deployment group what-if `
     -g rg-contoso-dev-eus2 `
     -f infra/modules/<module>.bicep `
     -p <params...>

   az deployment group create `
     -g rg-contoso-dev-eus2 `
     -f infra/modules/<module>.bicep `
     -p <params...>
   ```
   `defender.bicep` deploys at subscription scope instead — use `az deployment sub what-if`/`create` with `--location <region>` instead of `-g <resource group>`.

   Once all five are wired into `main.bicep` and uncommented, switch to deploying the whole thing at once via `main.bicep` + the appropriate `infra/env/<env>.bicepparam`, same as Phase 0.9 — deploying modules individually here is a Phase-1-only bootstrapping step, not the long-term pattern.
5. Confirm the Private Endpoint pattern actually works — see Validation below. A full network-path test (resolving the Key Vault's private DNS name and connecting from inside the VNet) needs a jumpbox or a running Container App, neither of which exists yet at this point in Phase 1 — treat that as a deferred check, not a blocker. Re-run it once Phase 2's Container Apps environment exists, or once you've deliberately decided on a jumpbox access pattern (see `docs/naming.md`'s note on `snet-jumpbox`/`AzureBastionSubnet`, still unimplemented as of this writing).

### Validation
Achievable now, no jumpbox/Container App required:
```powershell
az keyvault show -n <kv-name> -g rg-contoso-dev-eus2 `
  --query "{publicNetworkAccess:properties.publicNetworkAccess, rbac:properties.enableRbacAuthorization, softDelete:properties.enableSoftDelete, purgeProtection:properties.enablePurgeProtection}"
# Expect: Disabled / true / true / true

az network private-endpoint show -n pep-<kv-name> -g rg-contoso-dev-eus2 `
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status"
# Expect: Approved

az security pricing show --name KeyVaults --query pricingTier -o tsv
az security pricing show --name CloudPosture --query pricingTier -o tsv
```
Deferred until a jumpbox or AKS pod exists (see step 5 above):
- `Resolve-DnsName <kv-name>.vault.azure.net` from inside the VNet returns a `10.x.x.x` address, not a public IP.
- An actual connection to the vault succeeds from inside the VNet and fails from outside it.

### Exit criteria
- [ ] VNet with 4 subnets and NSGs deployed.
- [ ] Key Vault accessible only via Private Endpoint; no access policies (RBAC only); confirmed via `az keyvault show`, not just "should be."
- [ ] LA workspace receiving Activity Logs (`az monitor diagnostic-settings subscription show` lists the setting).
- [ ] 8 managed identities exist (`az identity list -g rg-contoso-dev-eus2 -o table`).
- [ ] Defender CSPM enabled at subscription scope.

---

## Phase 2 — Containers, Azure Container Apps, the first microservice

**Goal:** prove the full container path: write a service, containerize it, push to ACR, deploy to Azure Container Apps, ingress works, MI works.

Originally this phase built an AKS cluster. Three real deployment attempts hit a hard subscription vCPU quota wall no cluster configuration could satisfy — full account, including the exact errors, in `docs/decisions/ADR-002-aks-to-container-apps.md`. `acr.bicep` from the original plan is unaffected and unchanged; only the compute target changed.

### Learning objectives
- Dockerfile authoring, multi-stage builds, distroless base images.
- ACR with Private Endpoint, customer-managed keys, image scanning.
- Container Apps: Consumption-only environments, Workload Identity via direct UAMI binding, native KEDA scale rules.
- Resource requests (`cpu`/`memory`) per container app; no separate HPA object — scaling is part of the app's own definition.

### Components to deploy
1. `acr.bicep` — Azure Container Registry (Premium), Private Endpoint, customer-managed key from KV. *(Already built and deployed in Phase 2 as originally planned — nothing to redo here.)*
2. `container-apps-env.bicep` — the Consumption-only Managed Environment (the AKS-cluster equivalent), integrated into `snet-aca`, logs wired to the Phase 1 LA workspace.
3. `container-app.bicep` — a reusable per-service module (mirrors the loop pattern in `identity.bicep`), invoked once per microservice.
4. The `catalog-svc` microservice — read-only, returns canned data for now.

### Step-by-step

**2.1 Build the Container Apps environment.**
Bicep for `container-apps-env.bicep` should include:
- `vnetConfiguration.infrastructureSubnetId` → `snet-aca`, `internal: false` (external ingress for now — Phase 6's Front Door/APIM hardening is the point to reconsider locking this to internal-only).
- No `workloadProfiles` array — Consumption-only, which is what keeps this off the VM-family quota that blocked AKS.
- `appLogsConfiguration.destination = 'log-analytics'`, wired to the Phase 1 LA workspace via `listKeys()` at deploy time.

> **Claude Code prompt:**
> *"Generate `infra/modules/container-apps-env.bicep` for a Consumption-only Azure Container Apps Managed Environment integrated into an existing subnet (`snet-aca`, not delegated), external ingress, with `appLogsConfiguration` wired to an existing Log Analytics workspace via `listKeys()`. Output the environment ID and default domain."*

There's no `--attach-acr` step here — registry access is granted per Container App via `configuration.registries` + that app's own Managed Identity, not a cluster-wide kubelet identity.

**2.2 Write `catalog-svc`.**
Start small: a .NET 8 minimal API or Node Fastify that returns three hard-coded products. Add OpenTelemetry from day one (it's harder to retrofit).

> **Claude Code prompt:**
> *"Scaffold `apps/catalog-svc` as a .NET 8 minimal API with three endpoints: `GET /api/products`, `GET /api/products/{id}`, `GET /healthz`. Use the Microsoft.Azure.Cosmos SDK with `DefaultAzureCredential` (no keys). Add the OpenTelemetry packages and wire the App Insights exporter from `APPLICATIONINSIGHTS_CONNECTION_STRING` env var. For now, fall back to in-memory canned products if Cosmos config is absent. Include unit tests."*

**2.3 Containerize.**
Multi-stage Dockerfile, distroless or Alpine base. No root user. Read-only filesystem. Have Claude Code generate it.

**2.4 Push to ACR.**
```powershell
az acr build -r acrcontosodeveus -t catalog-svc:0.1.0 .
```
ACR Tasks builds in the cloud so you don't need local Docker for this — handy since Docker Desktop can be slow to start on Windows.

**2.5 Wire Workload Identity.**
Much simpler than the AKS version — `mi-catalog-svc-dev` already exists from Phase 1's `identity.bicep`; there's no federated-credential step and no Kubernetes ServiceAccount to annotate. `container-app.bicep` binds it directly:
```bicep
identity: {
  type: 'UserAssigned'
  userAssignedIdentities: {
    '<mi-catalog-svc-dev resource ID>': {}
  }
}
```
and references that same identity in `configuration.registries[].identity` for the ACR pull.

**2.6 Deploy `catalog-svc` via `container-app.bicep`.**

> **Claude Code prompt:**
> *"Generate `infra/modules/container-app.bicep` as a reusable module: params for `serviceName`, `image`, `containerAppsEnvironmentId`, `acrLoginServer`, `managedIdentityId`, `cpu`/`memory`, `minReplicas`/`maxReplicas`, and external ingress `targetPort`. Registry auth via the passed-in managed identity, no admin credentials. Output the app's FQDN."*

```powershell
az deployment group create `
  -g rg-contoso-dev-eus2 `
  -f infra/modules/container-app.bicep `
  -p serviceName=catalog-svc image=acrcontosodeveus.azurecr.io/catalog-svc:0.1.0 ...
```

**2.7 Validate the round-trip.**
```powershell
$fqdn = az containerapp show -n ca-catalog-svc-dev -g rg-contoso-dev-eus2 `
  --query properties.configuration.ingress.fqdn -o tsv

curl.exe "https://$fqdn/api/products"
```
No `Host` header trick needed — Container Apps gives every app its own HTTPS FQDN directly, unlike the shared AKS ingress IP the original plan used.

**2.8 Confirm scaling.**
Scaling is part of `container-app.bicep`'s own `template.scale` block (min/max replicas + an HTTP concurrency rule), not a separate HPA object — set `minReplicas`/`maxReplicas` when deploying 2.6 and confirm via `az containerapp revision list`.

### Exit criteria
- [ ] Container Apps environment healthy (`provisioningState: Succeeded`).
- [ ] Image scan on push reports no Critical or High CVEs — this still depends on the Containers Defender plan from Phase 6, same caveat as `acr.bicep` already notes; scanning happens at the registry level regardless of what compute pulls the image.
- [ ] `catalog-svc` reachable via its Container Apps FQDN and returns canned products.
- [ ] No connection strings or secrets in the Container App's Bicep definition or env vars.
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
3. `storage.bicep` — StorageV2 account with a `reviews-images` container (private; `pending/` and `approved/` are blob **path prefixes** inside it, not separate containers — see `docs/02-Architecture.md` §3.6's moderation flow) plus a separate `public-thumbnails` container; lifecycle policy; PE.
4. `redis.bicep` — Standard tier in dev (Premium with VNet injection in prod).
5. `service-bus.bicep` — namespace, queue `review-moderation-jobs`, topic `review-status-changed`.

### Step-by-step

Start with `cosmos.bicep`:

> **Claude Code prompt:**
> *"Generate `infra/modules/cosmos.bicep` for an Azure Cosmos DB for NoSQL account with: continuous backup, public network access disabled, Private Endpoint in `snet-pe`, a database `contoso-retail`, three containers (`products` PK `/categoryId`, `reviews` PK `/productId`, `chat-history` PK `/userId` with 30-day TTL). Use autoscale 1k-4k RU per container. Output the account endpoint."*

**3.1 Seed Cosmos with a real catalog.**
Write a small script (`scripts/seed-catalog.ts`) that loads 50 products from `data/products.json` into Cosmos. Run it once from your machine via Entra auth (you may need to temporarily grant your user the Data Contributor role on the container, then revoke).

**3.2 Update `catalog-svc` to read from Cosmos.**
- Use the official SDK with `DefaultAzureCredential` (no keys).
- Implement cache-aside with Redis: try Redis, miss → Cosmos → set in Redis with TTL 300s.
- Assign the service's MI the `Cosmos DB Built-in Data **Reader**` role scoped to the `products` container — not Contributor. `catalog-svc` is read-only per `docs/02-Architecture.md` §3.3; granting write access it never uses violates the project's own least-privilege principle (§4/§5).

> **Claude Code prompt:**
> *"Add to `cosmos.bicep` data-plane role assignments granting the `mi-catalog-svc` MI the `Cosmos DB Built-in Data Reader` role scoped to the `products` container only."*
>
> *"Update `catalog-svc` so it reads from Cosmos with cache-aside on Redis. Use `DefaultAzureCredential` for both. The Redis password is in Key Vault, but prefer using Entra auth for Redis Enterprise; for Standard Redis use Key Vault. Show me both options and pick the simpler one for dev."*

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
4. `moderation-worker` Container App with a native **KEDA** `azure-servicebus` scale rule keyed off queue depth (min 0 replicas — Consumption scales to zero when idle).
5. `assistant-svc` Container App.

### Step-by-step

**4.1 Deploy AI resources and validate PE access.**
Get a shell into a running replica to test MI access directly, no separate debug pod needed:
```powershell
az containerapp exec -n ca-catalog-svc-dev -g rg-contoso-dev-eus2 --command /bin/bash
```
Then, inside that shell:
```bash
az login --identity
az cognitiveservices account list-keys ...   # should work via MI
```

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

> **Claude Code prompt:**
> *"Build the `moderation-worker` as a Python `azure-servicebus` consumer. For each message:
> 1. Pull review from Cosmos.
> 2. Call AI Language `analyze_sentiment` and `extract_key_phrases`.
> 3. Call AI Content Safety on the text; if image present, call Vision tags + Content Safety on the image bytes.
> 4. If max severity < `MODERATION_THRESHOLD` (env var), set status to `approved`; else `needs-review`.
> 5. PATCH the Cosmos doc.
> 6. Publish `review.scored` to Event Hubs.
> Use `DefaultAzureCredential` everywhere. Add structured logging with correlation ID from the message properties. Deploy it via `container-app.bicep` with a native `azure-servicebus` KEDA scale rule, min 0 max 10 replicas."*

**4.3 Confirm the scale rule.**
`container-app.bicep`'s `template.scale.rules` — `azureQueue`/`azure-servicebus` type, min 0, max 10, `identity` set to the worker's own Managed Identity for KEDA auth (no separate identity or secret needed, same pattern as `catalog-svc`'s Phase 2 deployment).

**4.4 Build the assistant service (RAG).**
Indexer pulls products from Cosmos → AI Search `products-index` with vector fields generated by an indexer skillset calling the embedding model.

Chat orchestration in `assistant-svc`:
1. Embed user query.
2. Hybrid search in AI Search: BM25 + vector + semantic re-ranker → top-K.
3. Construct prompt: system instructions + retrieved snippets + user message.
4. Stream completion from OpenAI back to client.
5. Append citations.
6. Save conversation turn to `chat-history` Cosmos container.

> **Claude Code prompt:**
> *"Build `assistant-svc` as a FastAPI app with `POST /chat` that streams Server-Sent Events. Implementation:
> 1. Embed user query with `text-embedding-3-large` via Azure OpenAI.
> 2. Hybrid query Azure AI Search `products-index` (vector + BM25 + semantic re-ranker), top 5.
> 3. Compose prompt with strict system message confining the assistant to retail.
> 4. Call `gpt-4o` deployment with streaming; stream back to the client.
> 5. Append a citations object.
> 6. Persist the turn to Cosmos `chat-history`. Use MI auth. No keys."*

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

> **Claude Code prompt:**
> *"Generate the Stream Analytics query that consumes from `eventhub-domain`, filters events where `eventType = 'review.scored'`, computes 1-minute tumbling aggregates of count and avg sentiment grouped by `productCategory`, and writes to a Cosmos `realtime-metrics` container and a Power BI streaming dataset. Provide the Bicep for the SA job too."*

**5.3 Lakehouse build.**
Capture lands raw events as Avro in `bronze/`. A Synapse Spark notebook converts to Parquet under `silver/` partitioned by date. Another notebook builds the `gold/` star schema.

> **Claude Code prompt:**
> *"Write a Synapse Spark notebook (PySpark) that reads the Avro files Capture is dropping at `abfss://bronze@<adls>.dfs.core.windows.net/eventhub-domain/...`, parses the CloudEvents envelope, flattens to a table, and writes Parquet to `abfss://silver@.../reviews/` partitioned by `ingest_date`. Idempotent (use `mode='overwrite'` with partition overwrite mode `dynamic`)."*

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
2. **APIM** (`apim.bicep`) in front of public APIs with policies: JWT validation, rate limit, request body validation, correlation ID injection.
3. **Additional Defender plans**: Containers, SQL, Storage, App Service, Resource Manager. (CloudPosture and Key Vault were already enabled in `defender.bicep` back in Phase 1 — don't recreate them, extend that same module with the additional plans.)
4. **Microsoft Sentinel** with starter analytics rules.
5. **Network hardening**: NSGs reviewed, Private Endpoints everywhere, public access disabled on every data store.
6. **Observability**: Workbooks, alerts, dashboards.
7. **Cost**: budgets and action groups; auto-shutdown of dev outside business hours via a Logic App.
8. **DR drill**: practice the runbook.

### Step-by-step

**6.1 Build `apim.bicep`.**

> **Claude Code prompt:**
> *"Generate `infra/modules/apim.bicep` for an APIM Standard v2 instance in `snet-apim` with: managed identity, JWT validation policy template (validating tokens from External ID), rate-limit-by-key policy (20 calls/min per user), correlation header injection. Apply to a sample `catalog-api` operation."*

**6.2 Extend `defender.bicep`** with the additional plans listed above, rather than creating a second module — it's still one subscription-scoped resource type (`Microsoft.Security/pricings`), just more plan names.

**6.3 Front Door + WAF**, locking APIM/AppGW ingress so it's only reachable via Front Door.

**6.4 Sentinel analytics rules.**

> **Claude Code prompt:**
> *"Write KQL Sentinel analytics rules for: (1) impossible-travel sign-ins for users with the `Platform-Admin` role, (2) > 10 Key Vault access denials in 10 minutes from a single principal, (3) container privilege escalation events. Output as Bicep `analyticsRules` resources."*

**6.5 Alerts, budgets, DR drill** — see the sample alert set below and `docs/runbooks/dr.md`.

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
- Revisit AKS if the subscription's vCPU quota is ever increased — `aks.bicep` is kept, unused, for exactly this (see ADR-002).
- Add Dapr for service-to-service plumbing.
- Add Customer Lockbox in prod.
- Multi-region active-active with Cosmos multi-region writes and Front Door routing.
- Replace your own AI orchestration with **Azure AI Foundry** for evaluation, prompt flow, and observability of the AI pipeline.

---

*Next: read `04-Claude-Code-Playbook.md` for how to drive all of this with Claude Code.*
