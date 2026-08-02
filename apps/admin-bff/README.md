# admin-bff

**Introduced in:** Phase 6
**Stack:** .NET 8
**Purpose:** Backend-for-frontend for the admin UI (moderation queue). Strict RBAC.

## TODO
- [ ] Scaffold service.
- [ ] Add Dockerfile (multi-stage, distroless base, non-root).
- [ ] Wire OpenTelemetry → App Insights via env var `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- [ ] Add health endpoint `/healthz`.
- [ ] Add tests (xUnit / pytest / Vitest).
- [ ] Add Kustomize base under `../../k8s/base/admin-bff/`.

Refer to `docs/03-Implementation-Guide.md` Phase 6 and `docs/04-Claude-Code-Playbook.md` §4 for the prompt to generate this scaffold with Claude Code.
