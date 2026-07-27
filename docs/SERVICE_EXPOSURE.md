# Service exposure framework (Cloud Run)

K8s identity uses **NetworkPolicy default-deny** and **no public HTTPRoute** for
Hydra admin and Keto. Cloud Run expresses the same intent with an **exposure**
mode on `modules/cloudrun-service`.

Secrets stay **per GCP project** (unchanged). This document is about **network
and IAM reachability**, not Secret Manager placement.

## Two front doors

| Front door | Implementation | Hostname(s) | Routing | Cost |
|------------|----------------|-------------|---------|------|
| **API gateway** (default for product APIs) | [`edge/cloudflare-api-gateway`](../edge/cloudflare-api-gateway) Worker | `api.stawi.org` | Path prefix → Cloud Run | Free / ~$5 Workers |
| **Optional GCP path LB** | `apps/api-gateway` | `api.stawi.org` | Same paths via Global LB | ~$18/mo — not default |
| **Host edge LBs** | `edge-lb-*` | `accounts.*`, `oauth2.*`, `authz*`, optional `profile.*`… | One host rule per service | ~$18/mo each |

Path convention matches the K8s Gateway HTTPRoutes: clients call
`https://api.stawi.org/profile/…`; the gateway **strips** `/profile` before the
service so handlers stay at `/`. OAuth audiences remain
`https://api.stawi.org/profile` (`OAUTH2_RESOURCE_AUDIENCE`).

Host exceptions stay on edge LBs (login UI, OIDC, Keto) — same as cluster policy.

Extend product paths by editing
`edge/cloudflare-api-gateway/config/routes.prod.json` and deploying the Worker
(`gh workflow run edge-api-gateway.yml`).

## DNS does not mean public

Control-plane hosts (`authz*`, `oauth2-w`, optionally `tenancy`) still get
stable DNS via `edge-lb-identity` while Cloud Run IAM stays non-anonymous.

| Layer | What it does |
|-------|----------------|
| **DNS** | Name → LB IP |
| **HTTPS LB + serverless NEG** | Host or path rule → Cloud Run service |
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

## Hostname / path inventory (prod)

### Path gateway (`api-gateway` → `api.stawi.org`)

| Path | Cloud Run service | Project | Mode |
|------|-------------------|---------|------|
| `/profile` | identity-profile | stawi-identity | public |
| `/tenancy` | identity-tenancy | stawi-identity | **authenticated** (app OAuth + invoker) |
| `/identity` | identity-identity | stawi-identity | public |
| `/devices` | platform-devices | stawi-platform | public |
| `/settings` | platform-settings | stawi-platform | public |
| `/geolocation` | platform-geolocation | stawi-platform | public |
| `/files` | platform-files | stawi-platform | public |
| `/audit` … `/trustage` | operations-* | stawi-operations | public |

### Host exceptions (`edge-lb-*`)

| Hostname | Cloud Run service | Mode | Notes |
|----------|-------------------|------|--------|
| `accounts.stawi.org` | identity-authentication | public | Login UI |
| `oauth2.stawi.org` | identity-oauth2-hydra | **public** | OIDC authorize/token/JWKS (`serve public`) |
| `oauth2-w.stawi.org` | identity-oauth2-hydra-admin | **authenticated** | Hydra admin (`serve admin`) |
| `authz.stawi.org` | identity-authorization-keto-read | **authenticated** | Keto read API |
| `authz-w.stawi.org` | identity-authorization-keto-write | **authenticated** | Keto write API |
| `profile.stawi.org` … | product services | (varies) | Optional direct host; prefer path gateway |

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

1. Bootstrap **`stawi-api`** + cross-project LB IAM (see [`apps/api-gateway/README.md`](../apps/api-gateway/README.md)).
2. Apply **api-gateway** (path routes on `api.stawi.org`).
3. Apply **edge-lb-identity** (hosts including `oauth2-w`, `authz`, `authz-w`, accounts, oauth2).
4. Wait for Certificate Manager certs **ACTIVE** on new hostnames.
5. Apply **Keto** with identity + ops/platform invokers.
6. Apply **Hydra** (public + admin) with admin invokers + `advertise_admin_hostname`.
7. Apply **Frame** apps (identity, then ops/platform) so they use DNS control-plane URLs.
8. Confirm `https://api.stawi.org/profile/healthz` → **200**; anonymous curl to `authz*`, `oauth2-w` → **403**; `oauth2` public health → **200**.
9. Later: Shared VPC → flip Keto/admin to `exposure=private`.

## Tenancy (authenticated control plane)

| Surface | Exposure | Protection |
|---------|----------|------------|
| `tenancy.stawi.org` (all routes) | **authenticated** | Cloud Run `roles/run.invoker` + Google ID token; app OAuth/Keto still enforced in-process |
| `/_internal/sync/clients` | Same service | Hourly Scheduler OIDC as `identity-tenancy@…` (audience = `https://tenancy.stawi.org`) |

Invokers: identity Frame runtimes + ops/platform runtime SAs (`additional_invoker_members` in tfvars), same pattern as Keto.

Callers must mint a **Google identity token** (not only a product OAuth access token) for Cloud Run IAM. Frame’s Keto client already does this; HTTP/Connect clients that call tenancy need ID-token transport (or call via a service that has invoker).

## Out of scope (this pass)

- Secret Manager centralization (secrets stay per project)
- Full VPC / PSC mesh
- Splitting tenancy `_internal` into a second service
