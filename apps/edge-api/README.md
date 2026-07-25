# edge-api

Path-based public API edge for Cloud Run cutover (parity with K8s Gateway on `api.stawi.org`).

| Layer | Value |
|-------|--------|
| GCP | `identity` / `stawi-identity` (europe-west9) |
| Neon | none |
| Image | `caddy:2.8-alpine` |
| Public host | `api.stawi.org` (after domain mapping + DNS) |

Routes (prefix stripped, matching cluster `URLRewrite`):

| Path | Backend Cloud Run |
|------|-------------------|
| `/profile/*` | `identity-profile` |
| `/tenancy/*` | `identity-tenancy` |
| `/identity/*` | `identity-identity` |
| `/devices/*` | `platform-devices` |
| `/settings/*` | `platform-settings` |
| `/geolocation/*` | `platform-geolocation` |
| `/files/*` | `platform-files` |

See [docs/PUBLIC_EDGE_DNS.md](../../docs/PUBLIC_EDGE_DNS.md) and [config/public-edge.yaml](../../config/public-edge.yaml).
