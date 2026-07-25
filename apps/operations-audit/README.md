# operations-audit

Operations domain service (Cloud Run + Neon).

| | |
|--|--|
| GCP | `operations` → `stawi-operations` |
| Neon | `operations` |
| Image | `ghcr.io/antinvestor/service-authentication-audit:v1.54.52` |
| Path | `/audit` |
| DB extensions | uuid-ossp, pg_stat_statements, pg_trgm, btree_gin, btree_gist, timescaledb |

See [docs/DEPLOY_OPERATIONS.md](../../docs/DEPLOY_OPERATIONS.md).
