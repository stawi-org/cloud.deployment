# edge-lb-identity

Global HTTPS load balancer for identity public hostnames (Cloud Run domain mapping is **not** available in `europe-west9`).

| Host | Backend Cloud Run |
|------|-------------------|
| accounts.stawi.org | identity-authentication |
| oauth2.stawi.org | identity-oauth2-hydra |
| profile.stawi.org | identity-profile |
| tenancy.stawi.org | identity-tenancy |
| identity.stawi.org | identity-identity |

See [docs/PUBLIC_EDGE_DNS.md](../../docs/PUBLIC_EDGE_DNS.md).
