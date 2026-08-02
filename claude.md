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