# edge-lb-identity

OpenTofu-owned HTTPS edge for **identity host exceptions** only:

| Host | Backend Cloud Run | Exposure |
|------|-------------------|----------|
| accounts.stawi.org | identity-authentication | public (login UI) |
| oauth2.stawi.org | identity-oauth2-hydra | public (OIDC) |
| oauth2-w.stawi.org | identity-oauth2-hydra-admin | authenticated (IAM) |
| authz.stawi.org | identity-authorization-keto-read | authenticated (IAM) |
| authz-w.stawi.org | identity-authorization-keto-write | authenticated (IAM) |

**Product APIs are not here.** Use the path gateway:

- `https://api.stawi.org/profile`, `/tenancy`, `/identity`, …
- Worker: [`edge/cloudflare-api-gateway`](../../edge/cloudflare-api-gateway)

DNS does **not** make a service anonymous-public. Keto and Hydra admin still require `roles/run.invoker`. See [docs/SERVICE_EXPOSURE.md](../../docs/SERVICE_EXPOSURE.md).

Requires repo secret `CLOUDFLARE_API_TOKEN`. See [docs/PUBLIC_EDGE_DNS.md](../../docs/PUBLIC_EDGE_DNS.md).
