# Public edge DNS → Cloud Run (fully OpenTofu-managed)

Each public service has its own hostname. Front doors:

| Stack | OpenTofu app | GCP project | Hosts |
|-------|--------------|-------------|-------|
| Identity | `edge-lb-identity` | stawi-identity | accounts, oauth2, profile, tenancy, identity |
| Platform | `edge-lb-platform` | stawi-platform | devices, settings, geolocation, files |

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
```

OpenTofu will:

1. Ensure LB + certs exist  
2. Upsert Cloudflare ACME CNAMEs (validation)  
3. Upsert Cloudflare A records to the LB IPs (grey cloud by default)

Watch certs become ACTIVE:

```bash
gcloud certificate-manager certificates list --project=stawi-identity --location=global
gcloud certificate-manager certificates list --project=stawi-platform --location=global
```

## Host map

| Hostname | Service |
|----------|---------|
| accounts.stawi.org | identity-authentication |
| oauth2.stawi.org | identity-oauth2-hydra |
| profile.stawi.org | identity-profile |
| tenancy.stawi.org | identity-tenancy |
| identity.stawi.org | identity-identity |
| devices.stawi.org | platform-devices |
| settings.stawi.org | platform-settings |
| geolocation.stawi.org | platform-geolocation |
| files.stawi.org | platform-files |

## After certs ACTIVE

1. Smoke:

```bash
curl -sSI https://oauth2.stawi.org/health/ready
curl -sSI https://profile.stawi.org/healthz
curl -sSI https://devices.stawi.org/healthz
```

2. Hydra: set `advertise_public_hostname = true` in  
   `apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars` and re-apply.

3. Optional: set `cloudflare_proxied = true` in edge-lb tfvars for orange-cloud (SSL Full strict).

4. Optional: Cloudflare path aliases for legacy `api.stawi.org/*` (not in this repo).

## Drift / existing records

`edge-lb-*` roots self-heal via `data.cloudflare_dns_records` + `import` blocks (same pattern as `deployment.infra` 04-dns):

- Existing **A / AAAA / CNAME** for a traffic host is imported into `traffic_a` and replaced with the LB A record.
- Existing **ACME CNAMEs** are imported into `acme` if already present.

Re-apply after legacy cluster CNAMEs (orange-cloud) without hand-editing Cloudflare.

## Cost

Global external Application Load Balancer base charge applies per project (~\$15–25/mo each for identity + platform forwarding rules) plus traffic. Required substitute for domain mapping in europe-west9.
