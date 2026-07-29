# `finance-limits`

Cloud Run app on **`stawi-finance`** (`gcp.account` / `neon.account`: `finance`).

| Field | Value |
|-------|--------|
| Image | `ghcr.io/antinvestor/service-fintech-limits` |
| Path | `/limits` |
| OAuth client | `service-limits` (seeded by authentication tenancy migration) |
| Database | Neon (per-app project) |

See [docs/DEPLOY_FINANCE.md](../../docs/DEPLOY_FINANCE.md).
