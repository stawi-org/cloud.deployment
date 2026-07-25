# Public edge DNS → Cloud Run (host per service)

Each migrated Cloud Run service gets its **own hostname** on `stawi.org`.  
There is **no** Cloud Run path router / edge proxy.

**Registry:** [`config/public-edge.yaml`](../config/public-edge.yaml)  
**DNS today:** Cloudflare (orange-cloud on stawi.org).  
**Module:** [`modules/cloudrun-domain-mapping`](../modules/cloudrun-domain-mapping)

## Host map (prod)

| Hostname | Cloud Run service | Project | Health |
|----------|-------------------|---------|--------|
| `accounts.stawi.org` | `identity-authentication` | stawi-identity | Frame `/healthz` |
| `oauth2.stawi.org` | `identity-oauth2-hydra` | stawi-identity | Ory `/health/ready` |
| `profile.stawi.org` | `identity-profile` | stawi-identity | `/healthz` |
| `tenancy.stawi.org` | `identity-tenancy` | stawi-identity | `/healthz` |
| `identity.stawi.org` | `identity-identity` | stawi-identity | `/healthz` |
| `devices.stawi.org` | `platform-devices` | stawi-platform | `/healthz` |
| `settings.stawi.org` | `platform-settings` | stawi-platform | `/healthz` |
| `geolocation.stawi.org` | `platform-geolocation` | stawi-platform | `/healthz` |
| `files.stawi.org` | `platform-files` | stawi-platform | `/healthz` |

**Not public:** Keto read/write.

### Legacy `api.stawi.org/...` paths

K8s Gateway used path prefixes on `api.stawi.org`. If those URLs must keep working, implement **Cloudflare** routing (Worker, origin rules, or load balancer) to the hostnames above — **not** a Cloud Run edge service in this repo.

Example (conceptual):

```text
api.stawi.org/devices/*  →  devices.stawi.org/*   (optional prefix strip in CF)
api.stawi.org/profile/*  →  profile.stawi.org/*
```

## Prerequisites

### 1. Google domain verification

Cloud Run domain mapping needs the domain verified for your user/project:

```bash
gcloud domains verify stawi.org
gcloud domains list-user-verified
```

Until verified, leave `enable_domain_mapping = false` in each app’s `envs/stawi-prod.tfvars`.

### 2. Enable mapping per app

Each public app has:

```hcl
public_hostname       = "profile.stawi.org"  # example
enable_domain_mapping = false                # flip true after verify
```

Hydra also has `advertise_public_hostname` — set **true only after** DNS for `oauth2.stawi.org` points at the Cloud Run mapping (so Hydra advertises public URLs).

Helper:

```bash
./scripts/setup-public-edge-domains.sh status
./scripts/setup-public-edge-domains.sh verify-hint
./scripts/setup-public-edge-domains.sh enable-tfvars   # flips flags when ready
```

### 3. Apply and read DNS records

```bash
gh workflow run app-apply.yml -f app=identity-profile -f env=stawi-prod
# …

gcloud beta run domain-mappings describe --domain=profile.stawi.org \
  --region=europe-west9 --project=stawi-identity
```

Create the printed records in **Cloudflare** (prefer **DNS-only / grey cloud** until certificate is Active). Typical target: `ghs.googlehosted.com` CNAME.

Then optionally orange-cloud with SSL **Full (strict)**.

## Cutover order

1. Verify domain.  
2. Enable + apply domain mappings (all public apps).  
3. Add Cloudflare CNAMEs for each hostname.  
4. Wait until mapping certificate **Active**.  
5. Set `advertise_public_hostname = true` on Hydra; re-apply.  
6. Point remaining clients / env at the new hosts (or CF path aliases).  
7. Retire K8s Gateway routes for these hosts in `deployment.manifests` when traffic is confirmed.

## OpenTofu knobs (per app)

| Variable | Purpose |
|----------|---------|
| `public_hostname` | FQDN for this service |
| `enable_domain_mapping` | Create `google_cloud_run_domain_mapping` |
| `advertise_public_hostname` | Hydra only — use public host in OIDC URLs |

## Frame health

Frame default health path: **`GET /healthz`**.  
Ory Hydra/Keto: `/health/ready` (not Frame).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Mapping create: domain not verified | `gcloud domains verify stawi.org` |
| CertificatePending | Grey-cloud CNAME to Google target until Active |
| 404 on custom host | Mapping missing or DNS still on old origin |
| Hydra discovery still shows `*.run.app` | Set `advertise_public_hostname = true` after oauth2 DNS cutover |
