# web-frontend

**Introduced in:** Phase 2
**Stack:** React + Vite + TS
**Purpose:** Public PWA. MSAL.js for External ID sign-in. Calls APIM.

## TODO
- [ ] Scaffold service.
- [ ] Add Dockerfile (multi-stage, distroless base, non-root).
- [ ] Wire OpenTelemetry → App Insights via env var `APPLICATIONINSIGHTS_CONNECTION_STRING`.
- [ ] Add health endpoint `/healthz`.
- [ ] Add tests (xUnit / pytest / Vitest).
- [ ] Add Kustomize base under `../../k8s/base/web-frontend/`.

Refer to `docs/03-Implementation-Guide.md` Phase 2 and `docs/04-Claude-Code-Playbook.md` §4 for the prompt to generate this scaffold with Claude Code.
