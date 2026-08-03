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
- **Git Bash path-mangling on `az` commands.** If Claude Code's Bash tool runs under Git Bash/MSYS on Windows (rather than native PowerShell), MSYS auto-converts arguments that look like absolute Unix paths. Any `az ... --parameters` value starting with `/subscriptions/...` (any Azure resource ID) gets silently rewritten to something like `C:/Program Files/Git/subscriptions/...`. The dangerous part: `az deployment group what-if` still returns `"status": "Succeeded"` with the corrupted ID baked into the payload — it doesn't validate the ID is real, so this fails silently instead of erroring. Hit this for real wiring `keyvault.bicep`'s `subnetId`/`privateDnsZoneId` params. Fix: `export MSYS_NO_PATHCONV=1` before the command, or use native PowerShell. Get in the habit of spot-checking resource-ID parameters in `what-if` JSON output rather than trusting a green `status` alone.

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

## 4. Phase-by-phase prompts

These used to live here as a standalone list, separate from the steps they belonged to. They're now inlined directly into `docs/03-Implementation-Guide.md`, next to the step each one produces — e.g. the `network.bicep` prompt sits right at Phase 1 step 1, the `catalog-svc` scaffold prompt sits at Phase 2.2. Look there when you're actually executing a phase; the patterns in §3 above are what to reach for when you need something the guide doesn't already have a prompt for.

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
