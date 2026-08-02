# analytics-collector

**Introduced in:** Phase 5
**Stack:** Go or Node
**Purpose:** Receives raw client events, forwards to Event Hubs.

## TODO
- [ ] Scaffold service.
- [ ] Add Dockerfile (multi-stage, distroless base, non-root).
- [ ] Wire OpenTelemetry → App Insights via env var `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- [ ] Add health endpoint `/healthz`.
- [ ] Add tests (xUnit / pytest / Vitest).
- [ ] Add Kustomize base under `../../k8s/base/analytics-collector/`.

Refer to `docs/03-Implementation-Guide.md` Phase 5 and `docs/04-Claude-Code-Playbook.md` §4 for the prompt to generate this scaffold with Claude Code.
