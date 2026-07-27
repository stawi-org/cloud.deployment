# edge-lb-identity

Google **Certificate Manager** + Global HTTPS LB for **control-plane hosts only**
(grey-cloud DNS). See [docs/SSL_EDGE_POLICY.md](../../docs/SSL_EDGE_POLICY.md).

| Host | Backend | Exposure |
|------|---------|----------|
| oauth2-w.stawi.org | identity-oauth2-hydra-admin | authenticated (IAM) |
| authz.stawi.org | identity-authorization-keto-read | authenticated (IAM) |
| authz-w.stawi.org | identity-authorization-keto-write | authenticated (IAM) |

**Not on this LB:**

| Host | Via |
|------|-----|
| api.stawi.org | Cloudflare Worker path gateway |
| accounts.stawi.org | CF orange CNAME → Cloud Run `*.run.app` |
| oauth2.stawi.org | CF orange CNAME → Cloud Run `*.run.app` |

`cloudflare_proxied` is **forced false** so Cloudflare never MITMs Keto/Hydra admin.

Requires `CLOUDFLARE_API_TOKEN` (Zone DNS Edit for A + ACME CNAMEs).
