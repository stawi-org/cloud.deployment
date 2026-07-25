# Service exposure framework (Cloud Run)

K8s identity uses **NetworkPolicy default-deny** and **no public HTTPRoute** for
Hydra admin and Keto. Cloud Run expresses the same intent with an **exposure**
mode on `modules/cloudrun-service`.

Secrets stay **per GCP project** (unchanged). This document is about **network
and IAM reachability**, not Secret Manager placement.

## Modes

| Mode | Ingress | Anonymous (`allUsers`) | Cross-project callers | Typical use |
|------|---------|------------------------|----------------------|-------------|
| **public** | ALL | yes | n/a | Product APIs, Hydra **public**, accounts UI |
| **authenticated** | ALL | **no** — IAM `run.invoker` required | Yes (grant SA invoker) | **Keto read/write**, Hydra **admin** |
| **private** | INTERNAL_ONLY | no | Only via Shared VPC / PSC | After private networking lands |

### Why not only `private` today?

`INGRESS_TRAFFIC_INTERNAL_ONLY` rejects traffic that is not from a VPC path.
Ops/platform services in **other projects** currently call identity over
`*.run.app` HTTPS. Until Shared VPC / Private Service Connect is in place,
**`authenticated` is the robust multi-account default**: no anonymous internet,
but invoker-grantable cross-project.

Upgrade path: set `exposure = "private"` (Keto) / `admin_exposure = "private"`
(Hydra admin) when private networking is ready.

## Inventory (identity control plane)

| Service | Mode | Edge host | Notes |
|---------|------|-----------|--------|
| `identity-oauth2-hydra` (public) | **public** | `oauth2.stawi.org` | OIDC authorize/token/JWKS only (`serve public`) |
| `identity-oauth2-hydra-admin` | **authenticated** | **none** | `serve admin`; invoker allow-list |
| `identity-authorization-keto-read` | **authenticated** | **none** | Never on edge-lb-identity |
| `identity-authorization-keto-write` | **authenticated** | **none** | Same allow-list; higher risk surface |
| Frame product apps | **public** | accounts / api / profile | Unchanged |
| Tenancy product API | **public** | `api…/tenancy`, optional host | `_internal/*` must stay app-authz hardened |

## Invoker allow-list (Keto / Hydra admin)

Default members (identity project runtime SAs):

- `identity-authentication@…`
- `identity-identity@…`
- `identity-profile@…`
- `identity-tenancy@…`
- `identity-oauth2-hydra@…` (Hydra)
- Keto runtime SA (self + keep-warm OIDC)

Cross-project (ops/platform) — **opt-in** via tfvars:

```hcl
# apps/identity-authorization-keto/cloudrun/envs/stawi-prod.tfvars
additional_invoker_members = [
  "serviceAccount:operations-audit@stawi-operations.iam.gserviceaccount.com",
  "serviceAccount:operations-trustage@stawi-operations.iam.gserviceaccount.com",
  # …each ops/platform runtime that calls AUTHORIZATION_SERVICE_* URIs
]
```

Without these grants, ops/platform get **403** after Keto is locked down (expected).

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
| No HTTPRoute for Keto / Hydra admin | No edge-lb host for those services |
| HTTPRoute for Hydra public / accounts / api paths | `exposure=public` + edge-lb-identity |
| ClusterIP `*.identity.svc` | IAM-protected `*.run.app` (or internal URL later) |

## Operational checklist

1. Apply **Keto** first with identity invokers.
2. Add **ops/platform** SAs to `additional_invoker_members` before those domains call Keto.
3. Apply **Hydra** (public + new admin service). Point admin consumers at `admin_uri` output.
4. Confirm anonymous curl to keto-read/write and hydra-admin returns **403**.
5. Confirm identity Frame apps still authorize (invoker + app JWT).
6. Later: Shared VPC → flip Keto/admin to `private`.

## Out of scope (this pass)

- Secret Manager centralization (secrets stay per project)
- Full VPC / PSC mesh
- Splitting tenancy `_internal` into a second service (recommended follow-up)
