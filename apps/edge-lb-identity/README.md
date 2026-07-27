# edge-lb-identity

Google **Certificate Manager** + Global HTTPS LB for identity hostnames
(grey-cloud DNS). See [docs/SSL_EDGE_POLICY.md](../../docs/SSL_EDGE_POLICY.md).

| Host | Backend | Exposure |
|------|---------|----------|
| accounts.stawi.org | identity-authentication | public (`allUsers`) |
| oauth2.stawi.org | identity-oauth2-hydra | public (`allUsers`) |
| oauth2-w.stawi.org | identity-oauth2-hydra-admin | authenticated (IAM) |
| authz.stawi.org | identity-authorization-keto-read | authenticated (IAM) |
| authz-w.stawi.org | identity-authorization-keto-write | authenticated (IAM) |

**Not on this LB** (Cloudflare Worker):

| Host | Via |
|------|-----|
| api.stawi.org | Worker path gateway + Scalar only |

`cloudflare_proxied` is **forced false** so Cloudflare never MITMs these hosts.

Requires `CLOUDFLARE_API_TOKEN` (Zone DNS Edit for A + ACME CNAMEs).
