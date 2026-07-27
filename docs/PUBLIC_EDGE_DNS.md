# Edge DNS → Cloud Run (fully OpenTofu-managed)

## Front doors

| Surface | Implementation | SSL | Hosts |
|---------|----------------|-----|-------|
| Product + docs | Cloudflare Worker | CF Universal (orange) | **`api.stawi.org` only** |
| Login + OIDC + control plane | **Cloud Run domain mapping** (preferred, `europe-west1`) | Google managed cert | `accounts`, `oauth2`, `oauth2-w`, `authz`, `authz-w` |
| Interim | CF CNAME → `*.run.app` + Host rewrite | CF Universal | same hostnames |
| Break-glass LB | `edge-lb-identity` | Google Cert Manager (grey) | only if mappings fail |
| Platform/ops host LBs | retired | — | `hosts = {}` |

Canonical policy: [SSL_EDGE_POLICY.md](./SSL_EDGE_POLICY.md).

**DNS ≠ public** for control plane. `oauth2-w` / `authz*` still need
`roles/run.invoker` (no `allUsers`). `accounts` / `oauth2` are public apps.
See [SERVICE_EXPOSURE.md](./SERVICE_EXPOSURE.md).

**What OpenTofu manages**

| Layer | Resource |
|-------|----------|
| Global anycast IP | `google_compute_global_address` |
| Serverless NEGs → Cloud Run | `google_compute_region_network_endpoint_group` (in **service** project for the gateway) |
| HTTPS URL map (host or path rules) | `google_compute_url_map` |
| Managed TLS | Certificate Manager cert + map |
| Cert DNS validation | Cloudflare `CNAME` `_acme-challenge.<host>` |
| Traffic DNS | Cloudflare `A` `<host>` → LB IP |
| HTTP→HTTPS | Port 80 redirect on same IP |

**Cloud Run domain mapping** is available in **`europe-west1`** (preferred for
`accounts` / `oauth2*` / `authz*`). Global LB (`edge-lb-*`) is break-glass only.
See [REGION_MIGRATION_EUROPE_WEST1.md](./REGION_MIGRATION_EUROPE_WEST1.md).

**Registry:** [`config/public-edge.yaml`](../config/public-edge.yaml)  
**Modules:** [`modules/cloudrun-api-gateway`](../modules/cloudrun-api-gateway), [`modules/cloudrun-host-lb`](../modules/cloudrun-host-lb)

## One-time secret

Repository secret **`CLOUDFLARE_API_TOKEN`** with **Zone → DNS → Edit** on zone `stawi.org`  
(zone id `706bf604a333d866bb38c03bf643e79a`, same as `deployment.infra` 04-dns).

```bash
# GitHub → Settings → Secrets → Actions
# Name: CLOUDFLARE_API_TOKEN
# Value: <token>
```

CI injects it as `TF_VAR_cloudflare_api_token` for `edge-lb-*` and `api-gateway`.

## Apply (after secret is set)

```bash
# Product path gateway (api) + direct CNAME DNS for accounts/oauth2
gh workflow run edge-api-gateway.yml

# Control plane grey LB only (oauth2-w, authz*)
gh workflow run app-apply.yml -f app=edge-lb-identity -f env=stawi-prod

# Destroy retired product host LBs
gh workflow run app-apply.yml -f app=edge-lb-platform -f env=stawi-prod
gh workflow run app-apply.yml -f app=edge-lb-operations -f env=stawi-prod
```

Zone SSL mode: **Full (strict)** in the Cloudflare dashboard.

OpenTofu will:

1. Ensure LB + certs exist (new SANs for any new hostnames)  
2. Upsert Cloudflare ACME CNAMEs (validation)  
3. Upsert Cloudflare A records to the LB IPs (grey cloud by default)

Watch certs become ACTIVE:

```bash
gcloud certificate-manager certificates list --project=stawi-api --location=global
gcloud certificate-manager certificates list --project=stawi-identity --location=global
gcloud certificate-manager certificates list --project=stawi-platform --location=global
gcloud certificate-manager certificates list --project=stawi-operations --location=global
```

## Host map (prod)

### Product APIs — `api.stawi.org` only (Cloudflare Worker)

No per-service product hosts (`profile.stawi.org`, `devices.*`, …). Paths:

| Path | Service | Exposure |
|------|---------|----------|
| `/profile` | identity-profile | public |
| `/tenancy` | identity-tenancy | public edge (app OAuth) |
| `/identity` | identity-identity | public |
| `/devices` | platform-devices | public |
| `/settings` | platform-settings | public |
| `/geolocation` | platform-geolocation | public |
| `/files` | platform-files | public |
| `/audit`, `/formstore`, … | operations-* | public |

Full route table: `edge/cloudflare-api-gateway/config/routes.prod.json` and
`config/public-edge.yaml`.

### Login + OIDC (CF CNAME → Cloud Run, not Worker / not Google LB)

| Hostname | Service | Exposure |
|----------|---------|----------|
| accounts.stawi.org | identity-authentication | public |
| oauth2.stawi.org | identity-oauth2-hydra | public |

### Control plane (`edge-lb-identity`, grey-cloud Google LB)

| Hostname | Service | Exposure |
|----------|---------|----------|
| oauth2-w.stawi.org | identity-oauth2-hydra-admin | **authenticated** |
| authz.stawi.org | identity-authorization-keto-read | **authenticated** |
| authz-w.stawi.org | identity-authorization-keto-write | **authenticated** |

### Platform / operations host LBs

**Retired** (`hosts = {}`). Product traffic is path-only on `api.stawi.org`.

## After certs ACTIVE

1. Smoke:

```bash
# Path gateway (product APIs) — Worker
curl -sSI https://api.stawi.org/profile/readyz
curl -sSI https://api.stawi.org/devices/readyz
curl -sS https://api.stawi.org/_gateway/health

# Login + OIDC — Google LB (not Worker)
curl -sSI https://oauth2.stawi.org/health/ready
curl -sSI https://accounts.stawi.org/readyz

# Authenticated control plane — expect 403 without identity token
curl -sSI https://oauth2-w.stawi.org/health/ready
curl -sSI https://authz.stawi.org/health/ready
curl -sSI https://authz-w.stawi.org/health/ready
```

2. Hydra: `advertise_public_hostname` / `advertise_admin_hostname` in  
   `apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars`.

3. Optional: set `cloudflare_proxied = true` in edge-lb / api-gateway tfvars for orange-cloud (SSL Full strict).

4. Path aliases for `api.stawi.org/*` are owned by **`api-gateway`**, not Cloudflare Workers.

## Drift / existing records

`edge-lb-*` roots self-heal via `data.cloudflare_dns_records` + `import` blocks (same pattern as `deployment.infra` 04-dns):

- Existing **A / AAAA / CNAME** for a traffic host is imported into `traffic_a` and replaced with the LB A record.
- Existing **ACME CNAMEs** are imported into `acme` if already present.

Re-apply after legacy cluster CNAMEs (orange-cloud) without hand-editing Cloudflare.

## Cost

Global external Application Load Balancer base charge applies per front door
(~\$15–25/mo for each `edge-lb-*` / `api-gateway` that still has forwarding
rules) plus traffic. Prefer Cloud Run domain mapping in `europe-west1` to avoid
that cost for identity hosts.

The path gateway adds one LB in **stawi-api** and backend services (no extra
forwarding rules) in each domain project.
