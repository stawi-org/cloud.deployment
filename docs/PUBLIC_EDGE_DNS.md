# Public edge DNS → Cloud Run

Cutover of production hostnames from the K8s Gateway (`deployment.manifests`) to Cloud Run.

**Registry:** [`config/public-edge.yaml`](../config/public-edge.yaml)  
**DNS provider today:** Cloudflare (stawi.org zone — orange-cloud IPs).

## Target map (prod)

### Host exceptions (one service per hostname)

| Hostname | Cloud Run service | Project | Health |
|----------|-------------------|---------|--------|
| `accounts.stawi.org` | `identity-authentication` | `stawi-identity` | Frame **`/healthz`** |
| `oauth2.stawi.org` | `identity-oauth2-hydra` | `stawi-identity` | Ory **`/health/ready`** |

### Path-based API (`api.stawi.org`)

Cloud Run **domain mapping cannot path-route**. A dedicated edge app **`edge-api`** (Caddy) terminates `api.stawi.org` and reverse-proxies with **prefix strip** (parity with K8s `ReplacePrefixMatch: "/"`):

| Path | Backend |
|------|---------|
| `/profile/*` | `identity-profile` |
| `/tenancy/*` | `identity-tenancy` |
| `/identity/*` | `identity-identity` |
| `/devices/*` | `platform-devices` |
| `/settings/*` | `platform-settings` |
| `/geolocation/*` | `platform-geolocation` |
| `/files/*` | `platform-files` |

**Not public:** Keto read/write (private / mesh-style; no public DNS).

Backend URL template (stable, no custom domain required for backends):

```text
https://{service}-{project_number}.europe-west9.run.app
```

| Project | Number |
|---------|--------|
| stawi-identity | `721554040672` |
| stawi-platform | `305282281906` |

## Prerequisites

### 1. Google domain verification (required for domain mapping)

Cloud Run custom domains need the domain verified for your Google account/project:

```bash
# Interactive browser verification (Search Console / DNS TXT)
gcloud domains verify stawi.org

# Confirm
gcloud domains list-user-verified
```

Until this succeeds, leave `enable_domain_mapping = false` in:

- `apps/identity-authentication/cloudrun/envs/stawi-prod.tfvars`
- `apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars`
- `apps/edge-api/cloudrun/envs/stawi-prod.tfvars`

### 2. Deploy edge-api + services (no DNS change yet)

```bash
gh workflow run app-apply.yml -f app=edge-api -f env=stawi-prod
# identity + platform services already deployed
```

Smoke path router via **run.app** URL (before cutover):

```bash
EDGE=$(gcloud run services describe edge-api --project=stawi-identity --region=europe-west9 --format='value(status.url)')
curl -sS -o /dev/null -w '%{http_code}\n' "$EDGE/healthz"
# Expect 200
curl -sS -o /dev/null -w '%{http_code}\n' "$EDGE/devices/"   # backend may 401/404 — not 502
```

## Enable domain mappings

1. Verify domain (above).
2. Set `enable_domain_mapping = true` for auth, hydra, edge-api tfvars; commit + apply.
3. Read DNS records OpenTofu wants:

```bash
# After apply, from CI logs outputs or local tofu:
# module.domain.dns_records → typically CNAME → ghs.googlehosted.com
```

Or:

```bash
gcloud beta run domain-mappings describe --domain=oauth2.stawi.org \
  --region=europe-west9 --project=stawi-identity
```

4. In **Cloudflare** (stawi.org zone), create the records Google prints.
   - Prefer **DNS only** (grey cloud) until certificate status is **Active**.
   - Then optionally re-enable proxy (orange) with SSL mode **Full (strict)** once cert is good.

| Record | Type | Target (example) |
|--------|------|------------------|
| `oauth2` | CNAME | `ghs.googlehosted.com` |
| `accounts` | CNAME | `ghs.googlehosted.com` |
| `api` | CNAME | `ghs.googlehosted.com` |

Exact `rrdata` comes from the domain-mapping status — always use the values Google returns.

## Cutover sequence (production)

Do **host exceptions first**, then API:

1. **oauth2.stawi.org**  
   - Domain mapping Active → switch Cloudflare DNS from k8s/CF proxy to mapping target  
   - Set `advertise_public_hostname = true` on `identity-oauth2-hydra` and re-apply  
   - Smoke: `curl -sS https://oauth2.stawi.org/.well-known/openid-configuration | jq .issuer`

2. **accounts.stawi.org**  
   - Domain mapping Active → DNS cutover  
   - Smoke: `curl -sSI https://accounts.stawi.org/s/login` → 303/200

3. **api.stawi.org**  
   - Domain mapping on `edge-api` Active → DNS cutover  
   - Smoke each path: `/profile`, `/tenancy`, `/identity`, `/devices`, `/settings`, `/geolocation`, `/files`  
   - Update any remaining apps still using `*.run.app` for `OAUTH2_SERVICE_URI` to `https://oauth2.stawi.org` (post-hydra advertise)

4. Disable K8s Gateway routes / external-dns for cut-over hosts once traffic is confirmed (in `deployment.manifests` — out of band).

## OpenTofu knobs

| App | Variables |
|-----|-----------|
| `identity-oauth2-hydra` | `public_hostname`, `enable_domain_mapping`, `advertise_public_hostname` |
| `identity-authentication` | `public_hostname`, `enable_domain_mapping` |
| `edge-api` | `public_hostname`, `enable_domain_mapping`, project numbers for backends |

Modules:

- `modules/cloudrun-domain-mapping` — host → service mapping  
- `modules/cloudrun-keep-warm` — Scheduler pings (cheap warm)  
- `apps/edge-api` — path router  

## Frame health reminder

Frame default health endpoint is **`GET /healthz`** (not Ory `/health/ready`). Use `/healthz` for probes and keep-warm on Frame services.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|--------|-----|
| Domain mapping create 403 / not verified | No Search Console verification | `gcloud domains verify stawi.org` |
| Mapping stuck CertificatePending | DNS not pointing at Google target, or orange-cloud during issuance | Grey-cloud CNAME to `ghs.googlehosted.com` until Active |
| api.stawi.org 404 for /devices | Traffic still on old edge or edge-api not deployed | Confirm DNS → edge-api mapping; check Caddyfile secret |
| Backend 502 via edge-api | Wrong project_number / region in tfvars | Match live `gcloud run services describe` URL |
| Hydra still advertises run.app | `advertise_public_hostname=false` | Flip true after oauth2 DNS cutover |
