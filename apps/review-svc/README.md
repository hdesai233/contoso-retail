# review-svc

**Introduced in:** Phase 3
**Stack:** .NET 8 / Node
**Purpose:** Review CRUD. Writes to Cosmos, publishes to Service Bus + Event Hubs.

## TODO
- [ ] Scaffold service.
- [ ] Add Dockerfile (multi-stage, distroless base, non-root).
- [ ] Wire OpenTelemetry → App Insights via env var `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- [ ] Add health endpoint `/healthz`.
- [ ] Add tests (xUnit / pytest / Vitest).
- [ ] Add Kustomize base under `../../k8s/base/review-svc/`.

Refer to `docs/03-Implementation-Guide.md` Phase 3 and `docs/04-Claude-Code-Playbook.md` §4 for the prompt to generate this scaffold with Claude Code.
