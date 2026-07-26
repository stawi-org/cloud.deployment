# Service exposure framework (Cloud Run)

K8s identity uses **NetworkPolicy default-deny** and **no public HTTPRoute** for
Hydra admin and Keto. Cloud Run expresses the same intent with an **exposure**
mode on `modules/cloudrun-service`.

Secrets stay **per GCP project** (unchanged). This document is about **network
and IAM reachability**, not Secret Manager placement.

## DNS does not mean public

Every service should have a **stable hostname** (`*.stawi.org`) via the domain
edge LB (`edge-lb-identity`, `edge-lb-platform`, `edge-lb-operations`).

| Layer | What it does |
|-------|----------------|
| **DNS** | Name → LB IP |
| **HTTPS LB + serverless NEG** | Host rule → Cloud Run service |
| **Cloud Run IAM** (`roles/run.invoker`) | Who may invoke (anonymous vs allow-list) |
| **Ingress** | `ALL` vs `INTERNAL_ONLY` (VPC) |

Adding DNS for `authz.stawi.org` or `oauth2-w.stawi.org` does **not** open
anonymous internet access. Without `allUsers` invoker, unauthenticated calls
still receive **403**.

## Modes

| Mode | Ingress | Anonymous (`allUsers`) | Cross-project callers | Typical use |
|------|---------|------------------------|----------------------|-------------|
| **public** | ALL | yes | n/a | Product APIs, Hydra **public**, accounts UI |
| **authenticated** | ALL | **no** — IAM `run.invoker` required | Yes (grant SA invoker) | **Keto**, Hydra **admin** |
| **private** | INTERNAL_ONLY | no | Only via Shared VPC / PSC | After private networking lands |

### Why not only `private` today?

`INGRESS_TRAFFIC_INTERNAL_ONLY` rejects traffic that is not from a VPC path.
Ops/platform services in **other projects** call identity over HTTPS (custom
hosts or `*.run.app`). Until Shared VPC / Private Service Connect is in place,
**`authenticated` is the multi-account default**: no anonymous internet, but
invoker-grantable cross-project.

Upgrade path: set `exposure = "private"` (Keto) / `admin_exposure = "private"`
(Hydra admin) when private networking is ready.

## Hostname inventory (prod)

| Hostname | Cloud Run service | Mode | Notes |
|----------|-------------------|------|--------|
| `accounts.stawi.org` | identity-authentication | public | Login UI |
| `oauth2.stawi.org` | identity-oauth2-hydra | **public** | OIDC authorize/token/JWKS (`serve public`) |
| `oauth2-w.stawi.org` | identity-oauth2-hydra-admin | **authenticated** | Hydra admin (`serve admin`) |
| `authz.stawi.org` | identity-authorization-keto-read | **authenticated** | Keto read API |
| `authz-w.stawi.org` | identity-authorization-keto-write | **authenticated** | Keto write API |
| `profile.stawi.org` | identity-profile | public | Product |
| `tenancy.stawi.org` | identity-tenancy | public | Product API |
| `identity.stawi.org` | identity-identity | public | Product |
| `devices.stawi.org` … | platform-* | public | Platform product |
| `audit.stawi.org` … | operations-* | public | Operations product |

Registry: [`config/public-edge.yaml`](../config/public-edge.yaml).

## Invoker allow-list (Keto / Hydra admin)

### Default (identity project runtime SAs)

- `identity-authentication@…`
- `identity-identity@…`
- `identity-profile@…`
- `identity-tenancy@…`
- `identity-oauth2-hydra@…` (Hydra)
- Keto runtime SA (self + keep-warm OIDC)

### Cross-project (ops + platform) — required for multi-project

Configured in prod tfvars so **all** domain runtimes that call Keto / Hydra
admin can invoke:

```hcl
# apps/identity-authorization-keto/cloudrun/envs/stawi-prod.tfvars
# apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars (admin)
additional_invoker_members = [
  "serviceAccount:operations-audit@stawi-operations.iam.gserviceaccount.com",
  "serviceAccount:operations-formstore@stawi-operations.iam.gserviceaccount.com",
  # …all operations-* and platform-* runtime SAs
]
```

Callers use their Cloud Run **runtime service account** and Google identity
tokens (`roles/run.invoker`). Without a grant, cross-project calls get **403**.

## Application config (stable DNS)

Frame apps (`modules/frame-cloudrun-app`) in **prod** wire:

| Env | Value |
|-----|--------|
| `OAUTH2_SERVICE_URI` | `https://oauth2.stawi.org` |
| `OAUTH2_SERVICE_ADMIN_URI` | `https://oauth2-w.stawi.org` |
| `AUTHORIZATION_SERVICE_READ_URI` | Keto **read** Cloud Run URL (`*.run.app`) — gRPC client |
| `AUTHORIZATION_SERVICE_WRITE_URI` | Keto **write** Cloud Run URL (`*.run.app`) — gRPC client |
| `KETO_SERVICE_ADMIN_URI` | Same as write CR URL (when `enable_keto_admin`) |

DNS hosts `authz.stawi.org` / `authz-w.stawi.org` remain for humans and non-gRPC callers.
Frame’s authorizer uses **gRPC over TLS** to the Cloud Run URLs and mints a Google
ID token (runtime SA) for `roles/run.invoker`. Keto services use `use_http2` (h2c).

Cross-project callers still need invoker grants on keto read/write.

## Keep-warm on non-public services

`modules/cloudrun-keep-warm` supports OIDC:

```hcl
oidc_service_account_email = google_service_account.runtime.email
oidc_audience              = module.service.uri
```

That SA must be in `invoker_members`. Scheduler service agent needs
`roles/iam.serviceAccountUser` on the OIDC SA (wired for Keto).

## Module API

```hcl
module "service" {
  source          = "../../../modules/cloudrun-service"
  exposure        = "authenticated" # or public | private
  invoker_members = toset(["serviceAccount:…@….iam.gserviceaccount.com"])
  # optional overrides:
  # ingress         = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  # public_invoker  = false
}
```

Checks refuse `private` + `allUsers`, and warn when non-public has zero invokers.

## K8s ↔ Cloud Run mapping

| K8s | Cloud Run |
|-----|-----------|
| NetworkPolicy default-deny + allow gateway/prod NS | `authenticated` / `private` + invoker members |
| No HTTPRoute for Keto / Hydra admin | No **public** product semantics; **DNS still exists** for stable names |
| HTTPRoute for Hydra public / accounts / api paths | `exposure=public` + edge LB |
| ClusterIP `*.identity.svc` | IAM-protected hostnames / `*.run.app` |

## Operational checklist

1. Apply **edge-lb-identity** (hosts including `oauth2-w`, `authz`, `authz-w`).
2. Wait for Certificate Manager certs **ACTIVE** on new hostnames.
3. Apply **Keto** with identity + ops/platform invokers.
4. Apply **Hydra** (public + admin) with admin invokers + `advertise_admin_hostname`.
5. Apply **Frame** apps (identity, then ops/platform) so they use DNS control-plane URLs.
6. Confirm anonymous curl to `authz*`, `oauth2-w` → **403**; `oauth2` public health → **200**.
7. Later: Shared VPC → flip Keto/admin to `exposure=private`.

## Tenancy product vs internal routes

| Surface | Exposure | Protection |
|---------|----------|------------|
| Product API (`/tenancy/…`) | **public** + `tenancy.stawi.org` | App OAuth / product authz |
| `/_internal/*` | Same Cloud Run service today | **App-level** authz (service identity); not IAM-private like Keto |

Recommended follow-up: split `_internal` onto a second **authenticated** service
(same pattern as Hydra admin).

## Out of scope (this pass)

- Secret Manager centralization (secrets stay per project)
- Full VPC / PSC mesh
- Splitting tenancy `_internal` into a second service
