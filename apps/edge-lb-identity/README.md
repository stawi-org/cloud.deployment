# edge-lb-identity

Google **Certificate Manager** + Global HTTPS LB for **control-plane hosts only**
(grey-cloud DNS). See [docs/SSL_EDGE_POLICY.md](../../docs/SSL_EDGE_POLICY.md).

| Host | Backend | Exposure |
|------|---------|----------|
| oauth2-w.stawi.org | identity-oauth2-hydra-admin | authenticated (IAM) |
| authz.stawi.org | identity-authorization-keto-read | authenticated (IAM) |
| authz-w.stawi.org | identity-authorization-keto-write | authenticated (IAM) |

**Not on this LB** (Cloudflare Worker + Universal SSL instead):

| Host | Via |
|------|-----|
| api.stawi.org | Worker path gateway + Scalar |
| accounts.stawi.org | Worker host proxy |
| oauth2.stawi.org | Worker host proxy |

`cloudflare_proxied` is **forced false** in OpenTofu so Cloudflare never MITMs Keto/Hydra admin.

Requires `CLOUDFLARE_API_TOKEN` (Zone DNS Edit for A + ACME CNAMEs).
