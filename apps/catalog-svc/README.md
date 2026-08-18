# catalog-svc

**Introduced in:** Phase 2
**Stack:** .NET 8 minimal API
**Purpose:** Read-only product catalog. Cosmos read + Redis cache-aside.

## TODO
- [x] Scaffold service.
- [x] Add Dockerfile (multi-stage, distroless base, non-root).
- [x] Wire OpenTelemetry → App Insights via env var `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- [x] Add health endpoint `/healthz`.
- [x] Add tests (xUnit).
- [x] Deploy via `infra/modules/container-app.bicep` — no Kustomize/Kubernetes; see `docs/decisions/ADR-002-aks-to-container-apps.md`.

Refer to `docs/03-Implementation-Guide.md` Phase 2 for the Claude Code prompts used to build this.
