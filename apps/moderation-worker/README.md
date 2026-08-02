# moderation-worker

**Introduced in:** Phase 4
**Stack:** Python 3.11
**Purpose:** KEDA-scaled Service Bus consumer. Calls AI Language, Vision, Content Safety.

## TODO
- [ ] Scaffold service.
- [ ] Add Dockerfile (multi-stage, distroless base, non-root).
- [ ] Wire OpenTelemetry → App Insights via env var `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- [ ] Add health endpoint `/healthz`.
- [ ] Add tests (xUnit / pytest / Vitest).
- [ ] Add Kustomize base under `../../k8s/base/moderation-worker/`.

Refer to `docs/03-Implementation-Guide.md` Phase 4 and `docs/04-Claude-Code-Playbook.md` §4 for the prompt to generate this scaffold with Claude Code.
