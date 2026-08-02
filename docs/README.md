# Contoso Smart Retail Insights Platform
### A hands-on Azure learning project covering containers, Kubernetes, security, networking, identity, data, analytics, and AI

> **Goal**: build a real production-grade reference application on Azure end-to-end, using **Claude Code** as your pair-programmer. Every chapter of *Learning Microsoft Azure* (Jonah Andersson) lights up at least one component of this project.

---

## 1. The project in one paragraph

You are the lead engineer at **Contoso Retail**, a mid-size e-commerce company. The business wants a modern platform where shoppers can browse products, post text + image reviews, and chat with an AI shopping assistant. Internal merchandisers need dashboards showing review sentiment, top categories, and demand signals in near real-time. Everything must meet enterprise security and compliance standards. You will design and build this on Azure as a set of containerized microservices on AKS, fronted by API Management, backed by Cosmos DB / Azure SQL / Blob Storage, fed by Event Hubs into Synapse, and enriched by Azure OpenAI and Azure AI Services — with Entra ID, Key Vault, Managed Identities, Private Endpoints, and Defender for Cloud throughout.

## 2. What you will actually learn (mapped to your book)

| Azure pillar | This project teaches you... | Book chapter |
|---|---|---|
| **Compute / Containers** | Docker, ACR, AKS, multi-service deployment, HPA, KEDA | Ch. 3 |
| **Networking** | VNet, subnets, NSGs, Private Endpoints, Application Gateway + WAF, Front Door | Ch. 4 |
| **Storage & Databases** | Blob, Cosmos DB (NoSQL), Azure SQL, Redis Cache | Ch. 5 |
| **AI / ML** | Azure OpenAI, AI Language (sentiment), AI Vision, AI Search (vector RAG) | Ch. 6 |
| **Analytics** | Event Hubs, Stream Analytics, Synapse Analytics, Power BI | Ch. 7 |
| **Security / Identity** | Entra ID (workforce + External ID), Managed Identities, Key Vault, RBAC, Defender for Cloud, Sentinel | Ch. 9 |
| **Integration** | API Management, Service Bus, Event Grid | Ch. 10 |
| **DevSecOps / IaC** | Bicep, GitHub Actions, Azure DevOps pipelines, container scanning | Ch. 11–12 |
| **Monitoring** | Azure Monitor, App Insights, Log Analytics, KQL | Ch. 13 |
| **Developer Tools** | Azure CLI, `azd`, Bicep, Claude Code | Ch. 14 |

## 3. The documents in this project

Read them in this order:

1. **[`01-Requirements.md`](01-Requirements.md)** — Functional and non-functional requirements. This is the "what" and "why".
2. **[`02-Architecture.md`](02-Architecture.md)** — The reference architecture, component-by-component design decisions, data flows, security model, scaling model, and cost model. This is the "how it fits together".
3. **[`03-Implementation-Guide.md`](03-Implementation-Guide.md)** — A six-phase build plan. Each phase is a self-contained learning module with prerequisites, learning objectives, step-by-step instructions, validation steps, and exit criteria. This is the "how to build it".
4. **[`04-Claude-Code-Playbook.md`](04-Claude-Code-Playbook.md)** — How to use Claude Code effectively for this project: repo layout, CLAUDE.md content, prompt patterns, and concrete examples per phase. This is the "how to use Claude Code".

## 4. How long will this take?

| Phase | Focus | Realistic time (evenings/weekends) |
|---|---|---|
| 0 | Foundation: subscription, tooling, naming, Bicep skeleton | 1 week |
| 1 | Identity, network, secrets baseline | 1–2 weeks |
| 2 | Containers, AKS, first microservice | 2 weeks |
| 3 | Data plane: Cosmos, SQL, Blob, Redis | 1–2 weeks |
| 4 | AI: OpenAI, AI Search, sentiment, vision | 2 weeks |
| 5 | Analytics: Event Hubs, Stream Analytics, Synapse, Power BI | 1–2 weeks |
| 6 | Production hardening: WAF, Defender, Sentinel, SRE, cost | 1–2 weeks |

**Total: ~9–13 weeks** at ~6–10 hours/week. You can compress this aggressively or stretch it out.

## 5. What to do right now (the first 30 minutes) — Windows

You'll be working primarily from **PowerShell 7+** in **Windows Terminal**. See Phase 0 of the implementation guide for the full install list. Quick version:

1. Create an Azure subscription if you don't have one (free trial gives $200 credit and lots of free services).
2. Open **PowerShell 7** as Administrator and install the essentials with `winget`:
   ```powershell
   winget install --id Microsoft.PowerShell -e
   winget install --id Microsoft.WindowsTerminal -e
   winget install --id Git.Git -e
   winget install --id Microsoft.AzureCLI -e
   winget install --id Microsoft.Azd -e
   winget install --id GitHub.cli -e
   winget install --id OpenJS.NodeJS.LTS -e
   ```
3. Close and reopen Windows Terminal, then run `az login` and `az account show` to confirm the right subscription is active.
4. Read `01-Requirements.md` end-to-end (~20 min).
5. Skim `02-Architecture.md` to get a mental model (~15 min).
6. Start Phase 0 in `03-Implementation-Guide.md` — it lists the rest of the toolchain (Docker, kubectl, helm, .NET SDK, Python, VS Code) and calls out where WSL2 makes life easier.

## 6. Guiding principles for this project

- **Build it small, then make it real.** First pass uses public endpoints and free tiers. Second pass adds private networking, custom domains, WAF, and SKU upgrades. Don't try to build the final architecture on day one.
- **Everything is code.** No clicking in the portal beyond exploration. Bicep + GitHub Actions own the truth.
- **Identity is the new perimeter.** Every service-to-service call uses Managed Identity. No connection strings in code. Ever.
- **Cost discipline.** Tag everything, set budgets per environment, shut down dev nightly, prefer serverless and consumption tiers until you need scale.
- **Use Claude Code aggressively.** Generate Bicep, write Dockerfiles, scaffold microservices, draft KQL queries, explain error messages, refactor pipelines. See `04-Claude-Code-Playbook.md`.

---

*Built as a learning companion to* Learning Microsoft Azure: Cloud Computing and Development Fundamentals *by Jonah Andersson (O'Reilly).*
