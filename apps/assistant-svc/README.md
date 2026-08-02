# assistant-svc

**Introduced in:** Phase 4
**Stack:** Python FastAPI
**Purpose:** AI shopping assistant. RAG via AI Search + Azure OpenAI. Streams SSE.

## TODO
- [ ] Scaffold service.
- [ ] Add Dockerfile (multi-stage, distroless base, non-root).
- [ ] Wire OpenTelemetry → App Insights via env var `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- [ ] Add health endpoint `/healthz`.
- [ ] Add tests (xUnit / pytest / Vitest).
- [ ] Add Kustomize base under `../../k8s/base/assistant-svc/`.

Refer to `docs/03-Implementation-Guide.md` Phase 4 and `docs/04-Claude-Code-Playbook.md` §4 for the prompt to generate this scaffold with Claude Code.
