# cloudrun-service

Cloud Run v2 service with an **exposure** framework for public vs private APIs.

## Exposure modes

| Mode | Ingress | `allUsers` invoker | Use for |
|------|---------|-------------------|---------|
| `public` | `INGRESS_TRAFFIC_ALL` | yes (default) | Product APIs, Hydra **public**, accounts UI |
| `authenticated` | `INGRESS_TRAFFIC_ALL` | **no** | Control plane that must stay non-anonymous but still accept **cross-project** Cloud Run callers without Shared VPC (Keto, Hydra **admin**) |
| `private` | `INGRESS_TRAFFIC_INTERNAL_ONLY` | **no** | Same-VPC / internal-only once Shared VPC or private path exists |

### `authenticated` vs `private`

- **authenticated**: URL is on the Google frontend, but **IAM `run.invoker` is required**. Anonymous internet gets 403. Cross-project callers work if granted invoker.
- **private**: Network-level internal only. Callers need VPC / Serverless VPC Access / PSC. Prefer when identity + consumers share a VPC.

K8s parity (NetworkPolicy + no HTTPRoute) ≈ **`authenticated` today**, **`private` when VPC is ready**.

## Invokers

```hcl
module "service" {
  source           = "../cloudrun-service"
  exposure         = "authenticated"
  invoker_members  = [
    "serviceAccount:identity-tenancy@stawi-identity.iam.gserviceaccount.com",
    "serviceAccount:identity-authentication@stawi-identity.iam.gserviceaccount.com",
  ]
  # public_invoker is derived; do not set true for authenticated/private
}
```

Keep-warm against non-public services must use OIDC (`modules/cloudrun-keep-warm` `oidc_service_account_email`) and include that SA in `invoker_members`.

## Backward compatibility

- `public_invoker = null` (default) → derived from `exposure`
- Explicit `public_invoker = true/false` overrides derivation
- Explicit `ingress` overrides exposure-derived ingress
