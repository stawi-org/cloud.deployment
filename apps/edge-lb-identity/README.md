# edge-lb-identity

OpenTofu-owned public edge for identity hostnames:

- Global HTTPS LB + serverless NEGs → Cloud Run
- Certificate Manager (Google-managed TLS)
- Cloudflare DNS (`A` + ACME `CNAME`) via provider token

Classic Cloud Run domain mapping is **not** available in `europe-west9`.

| Host | Backend Cloud Run | Exposure |
|------|-------------------|----------|
| accounts.stawi.org | identity-authentication | public |
| oauth2.stawi.org | identity-oauth2-hydra | public (OIDC) |
| oauth2-w.stawi.org | identity-oauth2-hydra-admin | authenticated (IAM) |
| authz.stawi.org | identity-authorization-keto-read | authenticated (IAM) |
| authz-w.stawi.org | identity-authorization-keto-write | authenticated (IAM) |
| profile.stawi.org | identity-profile | public |
| tenancy.stawi.org | identity-tenancy | public product |
| identity.stawi.org | identity-identity | public |

DNS does **not** make a service anonymous-public. Keto and Hydra admin still require `roles/run.invoker`. See [docs/SERVICE_EXPOSURE.md](../../docs/SERVICE_EXPOSURE.md).

Requires repo secret `CLOUDFLARE_API_TOKEN`. See [docs/PUBLIC_EDGE_DNS.md](../../docs/PUBLIC_EDGE_DNS.md).
