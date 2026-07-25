# Edge DNS → Cloud Run (fully OpenTofu-managed)

Every service gets a stable hostname. Front doors:

| Stack | OpenTofu app | GCP project | Hosts |
|-------|--------------|-------------|-------|
| Identity | `edge-lb-identity` | stawi-identity | accounts, oauth2, **oauth2-w**, **authz**, **authz-w**, profile, tenancy, identity |
| Platform | `edge-lb-platform` | stawi-platform | devices, settings, geolocation, files |
| Operations | `edge-lb-operations` | stawi-operations | audit, formstore, queuestore, redirect, thesa, trustage |

**DNS ≠ public.** Control-plane hosts (`oauth2-w`, `authz`, `authz-w`) are on the
edge LB for stable names and TLS, but Cloud Run IAM still requires
`roles/run.invoker` (no `allUsers`). See [SERVICE_EXPOSURE.md](./SERVICE_EXPOSURE.md).

**What OpenTofu manages**

| Layer | Resource |
|-------|----------|
| Global anycast IP | `google_compute_global_address` |
| Serverless NEGs → Cloud Run | `google_compute_region_network_endpoint_group` |
| HTTPS URL map (host rules) | `google_compute_url_map` |
| Managed TLS | Certificate Manager cert + map |
| Cert DNS validation | Cloudflare `CNAME` `_acme-challenge.<host>` |
| Traffic DNS | Cloudflare `A` `<host>` → LB IP |
| HTTP→HTTPS | Port 80 redirect on same IP |

**Why not Cloud Run domain mapping?** Not available in `europe-west9` (API returns 501).

**Registry:** [`config/public-edge.yaml`](../config/public-edge.yaml)  
**Module:** [`modules/cloudrun-host-lb`](../modules/cloudrun-host-lb)

## One-time secret

Repository secret **`CLOUDFLARE_API_TOKEN`** with **Zone → DNS → Edit** on zone `stawi.org`  
(zone id `706bf604a333d866bb38c03bf643e79a`, same as `deployment.infra` 04-dns).

```bash
# GitHub → Settings → Secrets → Actions
# Name: CLOUDFLARE_API_TOKEN
# Value: <token>
```

CI injects it as `TF_VAR_cloudflare_api_token` for `edge-lb-*` only.

## Apply (after secret is set)

```bash
gh workflow run app-apply.yml -f app=edge-lb-identity -f env=stawi-prod
gh workflow run app-apply.yml -f app=edge-lb-platform -f env=stawi-prod
gh workflow run app-apply.yml -f app=edge-lb-operations -f env=stawi-prod
```

OpenTofu will:

1. Ensure LB + certs exist (new SANs for any new hostnames)  
2. Upsert Cloudflare ACME CNAMEs (validation)  
3. Upsert Cloudflare A records to the LB IPs (grey cloud by default)

Watch certs become ACTIVE:

```bash
gcloud certificate-manager certificates list --project=stawi-identity --location=global
gcloud certificate-manager certificates list --project=stawi-platform --location=global
gcloud certificate-manager certificates list --project=stawi-operations --location=global
```

## Host map (prod)

### Identity (`edge-lb-identity`)

| Hostname | Service | Exposure |
|----------|---------|----------|
| accounts.stawi.org | identity-authentication | public |
| oauth2.stawi.org | identity-oauth2-hydra | public (OIDC) |
| oauth2-w.stawi.org | identity-oauth2-hydra-admin | **authenticated** |
| authz.stawi.org | identity-authorization-keto-read | **authenticated** |
| authz-w.stawi.org | identity-authorization-keto-write | **authenticated** |
| profile.stawi.org | identity-profile | public |
| tenancy.stawi.org | identity-tenancy | public product |
| identity.stawi.org | identity-identity | public |

### Platform (`edge-lb-platform`)

| Hostname | Service |
|----------|---------|
| devices.stawi.org | platform-devices |
| settings.stawi.org | platform-settings |
| geolocation.stawi.org | platform-geolocation |
| files.stawi.org | platform-files |

### Operations (`edge-lb-operations`)

| Hostname | Service |
|----------|---------|
| audit.stawi.org | operations-audit |
| formstore.stawi.org | operations-formstore |
| queuestore.stawi.org | operations-queuestore |
| redirect.stawi.org | operations-redirect |
| thesa.stawi.org | operations-thesa |
| trustage.stawi.org | operations-trustage |

## After certs ACTIVE

1. Smoke:

```bash
# Public
curl -sSI https://oauth2.stawi.org/health/ready
curl -sSI https://profile.stawi.org/healthz
curl -sSI https://devices.stawi.org/healthz
curl -sSI https://audit.stawi.org/healthz

# Authenticated control plane — expect 403 without identity token
curl -sSI https://oauth2-w.stawi.org/health/ready
curl -sSI https://authz.stawi.org/health/ready
curl -sSI https://authz-w.stawi.org/health/ready
```

2. Hydra: `advertise_public_hostname` / `advertise_admin_hostname` in  
   `apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars`.

3. Optional: set `cloudflare_proxied = true` in edge-lb tfvars for orange-cloud (SSL Full strict).

4. Optional: Cloudflare path aliases for legacy `api.stawi.org/*` (see `public-edge.yaml`).

## Drift / existing records

`edge-lb-*` roots self-heal via `data.cloudflare_dns_records` + `import` blocks (same pattern as `deployment.infra` 04-dns):

- Existing **A / AAAA / CNAME** for a traffic host is imported into `traffic_a` and replaced with the LB A record.
- Existing **ACME CNAMEs** are imported into `acme` if already present.

Re-apply after legacy cluster CNAMEs (orange-cloud) without hand-editing Cloudflare.

## Cost

Global external Application Load Balancer base charge applies per project
(~\$15–25/mo each for identity + platform + operations forwarding rules) plus
traffic. Required substitute for domain mapping in europe-west9.
