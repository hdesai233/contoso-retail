# Contoso Smart Retail Insights Platform

A hands-on Azure learning project. Full context, requirements, architecture, phased build plan, and Claude Code playbook live in [`docs/`](docs/).

## Start here
1. Read [`docs/README.md`](docs/README.md) — the project overview.
2. Read [`docs/01-Requirements.md`](docs/01-Requirements.md).
3. Skim [`docs/02-Architecture.md`](docs/02-Architecture.md).
4. Follow [`docs/03-Implementation-Guide.md`](docs/03-Implementation-Guide.md) phase by phase.
5. Use [`docs/04-Claude-Code-Playbook.md`](docs/04-Claude-Code-Playbook.md) to drive it all with Claude Code.

## Verify your local toolchain
```powershell
.\scripts\verify-tools.ps1
```

## Repo layout
```
apps/                       Microservices source code (one folder per service)
infra/                      Bicep IaC (main.bicep + modules/ + env/)
k8s/                        Kustomize manifests (base/ + overlays/{dev,test,prod})
.github/workflows/          CI/CD pipelines
docs/                       All project documentation
scripts/                    Utility scripts (seeding, verification, ops helpers)
data/                       Seed data (e.g. products.json)
CLAUDE.md                   Durable project context for Claude Code
azure.yaml                  Azure Developer CLI (azd) configuration
```
