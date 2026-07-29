# `finance-operations`

Cloud Run app on **`stawi-finance`** (`gcp.account` / `neon.account`: `finance`).

Fintech **operations** API at path `/operations` (distinct from `operations-*` platform apps on `stawi-operations`).

| Field | Value |
|-------|--------|
| Image | `ghcr.io/antinvestor/service-fintech-operations` |
| Path | `/operations` |
| OAuth client | `service-operations` |
| Database | Neon (per-app project) |

See [docs/DEPLOY_FINANCE.md](../../docs/DEPLOY_FINANCE.md).
