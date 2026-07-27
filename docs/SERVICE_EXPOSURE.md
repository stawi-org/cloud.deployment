# Service exposure framework (Cloud Run)

K8s identity uses **NetworkPolicy default-deny** and **no public HTTPRoute** for
Hydra admin and Keto. Cloud Run expresses the same intent with an **exposure**
mode on `modules/cloudrun-service`.

Secrets stay **per GCP project** (unchanged). This document is about **network
and IAM reachability**, not Secret Manager placement.

## Two front doors

| Front door | Implementation | Hostname(s) | Routing | Cost |
|------------|----------------|-------------|---------|------|
| **Public edge** | [`edge/cloudflare-api-gateway`](../edge/cloudflare-api-gateway) | `api` / `accounts` / `oauth2` | CF Universal SSL (orange) → `*.run.app` | Free / ~$5 |
| **Control plane LB** | `edge-lb-identity` | `oauth2-w`, `authz`, `authz-w` | Google Cert Manager (grey) | ~$18/mo |

Policy: [SSL_EDGE_POLICY.md](./SSL_EDGE_POLICY.md). No product hosts (`profile.stawi.org`, …).

Path convention matches the K8s Gateway HTTPRoutes: clients call
`https://api.stawi.org/profile/…`; the gateway **strips** `/profile` before the
service so handlers stay at `/`. OAuth audiences remain
`https://api.stawi.org/profile` (`OAUTH2_RESOURCE_AUDIENCE`).

Host exceptions stay on edge LBs (login UI, OIDC, Keto) — same as cluster policy.

Extend product paths by editing
`edge/cloudflare-api-gateway/config/routes.prod.json` and deploying the Worker
(`gh workflow run edge-api-gateway.yml`).

### API documentation hub (Scalar)

`https://api.stawi.org/` and `/docs` serve a **[Scalar](https://github.com/scalar/scalar)**
multi-document hub. Each route with `docs.enabled: true` and an `openapi_path`
(default `/openapi.yaml`) appears in the document switcher. Specs are loaded via
the gateway (`/{prefix}/openapi.yaml`); the Worker rewrites OpenAPI `servers` to
`https://api.stawi.org/{prefix}` so Try-it and samples use the path gateway.

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

### Product paths (`api.stawi.org` — Cloudflare Worker)

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

### Hostnames

| Hostname | Cloud Run service | Mode | Notes |
|----------|-------------------|------|--------|
| `api.stawi.org/*` | product Cloud Run | public (path) | CF Worker |
| `accounts.stawi.org` | identity-authentication | public | CF Worker |
| `oauth2.stawi.org` | identity-oauth2-hydra | public OIDC | CF Worker |
| `oauth2-w.stawi.org` | identity-oauth2-hydra-admin | **authenticated** | Google LB grey |
| `authz.stawi.org` | identity-authorization-keto-read | **authenticated** | Google LB grey |
| `authz-w.stawi.org` | identity-authorization-keto-write | **authenticated** | Google LB grey |

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
| Product `*_SERVICE_URI` | `https://api.stawi.org/<path>` (profile, tenancy, devices, files, …) |
| `PERMISSIONS_REGISTRATION_URL` | `https://api.stawi.org/tenancy/_internal/register/permissions` |
| `OAUTH2_SERVICE_URI` | `https://oauth2.stawi.org` |
| `OAUTH2_SERVICE_ADMIN_URI` | `https://oauth2-w.stawi.org` |
| `AUTHORIZATION_SERVICE_READ_URI` | `https://authz.stawi.org` |
| `AUTHORIZATION_SERVICE_WRITE_URI` | `https://authz-w.stawi.org` |
| `KETO_SERVICE_ADMIN_URI` | `https://authz-w.stawi.org` (when `enable_keto_admin`) |

Product HTTP goes through **`api.stawi.org`**. Hydra/Keto use their stable DNS
hosts. Frame’s authorizer talks **gRPC over TLS** to `authz*` and mints a Google
ID token (runtime SA) with audience = that host; Keto Cloud Run accepts those
hostnames via `custom_audiences` and `use_http2` (h2c).

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

1. Follow cutover in [SSL_EDGE_POLICY.md](./SSL_EDGE_POLICY.md) (token scopes → Worker → edge-lb-identity → retire platform/ops LBs).
2. Zone SSL **Full (strict)**.
3. Apply **Keto** / **Hydra** invokers; Frame apps use `api.stawi.org` path bases.
4. Smoke: api health/docs, accounts, oauth2 ready; `authz*` / `oauth2-w` → **403** without identity token.

## Tenancy (authenticated control plane)

| Surface | Exposure | Protection |
|---------|----------|------------|
| `api.stawi.org/tenancy` | **public edge** (app OAuth) | Cloud Run `allUsers` invoker + in-process OAuth/Keto |
| `/_internal/sync/clients` | Same service | Scheduler OIDC as `identity-tenancy@…` (audience = Cloud Run service URI) |

**Why allUsers (not IAM-only like Keto):** Connect S2S clients (`common/connection`) send **product OAuth** only. Frame dual-auth (`X-Serverless-Authorization`) is not wired on Connect yet. IAM-only tenancy made login fail: no `access_id` → token enrichment reject → browser **403** on `oauth2.stawi.org/oauth2/token`.

RPCs still require OAuth (no anonymous business data). Optional `custom_audiences` (`https://api.stawi.org`, `…/tenancy`) remain for dual-auth callers.

## Out of scope (this pass)

- Secret Manager centralization (secrets stay per project)
- Full VPC / PSC mesh
- Splitting tenancy `_internal` into a second service
