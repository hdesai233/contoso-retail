# Scripts

Utility scripts for development and operations.

| Script | Purpose |
|---|---|
| `verify-tools.ps1` | Check that your local Windows toolchain is complete before starting Phase 0. |
| `seed-catalog.ts` | *(Phase 3)* Load `data/products.json` into the Cosmos `products` container. |

## Adding scripts
- PowerShell scripts get `.ps1` extension and include a comment-based help block at the top.
- TypeScript/Node scripts live at the repo root or in a service's folder if service-specific.
- Anything requiring Azure access should use `DefaultAzureCredential` — no keys.
