# Public edge DNS → Cloud Run (host per service)

Each migrated Cloud Run service gets its **own hostname** on `stawi.org`.  
There is **no** Cloud Run path router.

**Important:** Classic Cloud Run **domain mapping is not available in `europe-west9`**.  
Public hostnames use a **Global HTTPS Application Load Balancer** + **Certificate Manager**
(serverless NEGs → Cloud Run) instead.

**Registry:** [`config/public-edge.yaml`](../config/public-edge.yaml)  
**OpenTofu:** `apps/edge-lb-identity`, `apps/edge-lb-platform`  
**Module:** [`modules/cloudrun-host-lb`](../modules/cloudrun-host-lb)

## Host map (prod)

### Identity LB (`edge-lb-identity` → one anycast IP)

| Hostname | Cloud Run service |
|----------|-------------------|
| `accounts.stawi.org` | `identity-authentication` |
| `oauth2.stawi.org` | `identity-oauth2-hydra` |
| `profile.stawi.org` | `identity-profile` |
| `tenancy.stawi.org` | `identity-tenancy` |
| `identity.stawi.org` | `identity-identity` |

### Platform LB (`edge-lb-platform` → second anycast IP)

| Hostname | Cloud Run service |
|----------|-------------------|
| `devices.stawi.org` | `platform-devices` |
| `settings.stawi.org` | `platform-settings` |
| `geolocation.stawi.org` | `platform-geolocation` |
| `files.stawi.org` | `platform-files` |

**Not public:** Keto.

### Legacy `api.stawi.org/...`

Optional **Cloudflare** path routing to the hosts above (not in this repo).

## Deploy

```bash
gh workflow run app-apply.yml -f app=edge-lb-identity -f env=stawi-prod
gh workflow run app-apply.yml -f app=edge-lb-platform -f env=stawi-prod
```

### Outputs to collect after apply

```text
ip_address                  # A record target (DNS-only recommended initially)
dns_authorization_records   # Certificate Manager CNAMEs for cert validation
```

From CI logs or:

```bash
# After apply, tofu outputs are in the job log "Outputs:" section
```

## Cloudflare DNS (two steps)

### A) Certificate validation (required first)

For each hostname, Certificate Manager emits a **CNAME** (often under `_acme-challenge_...` or similar).  
Add those records in Cloudflare (**DNS-only / grey cloud**).

Wait until the certificate is **ACTIVE**.

### B) Traffic cutover

Point each hostname at the LB IP:

| Hostnames | Type | Content |
|-----------|------|---------|
| accounts, oauth2, profile, tenancy, identity | **A** | identity LB `ip_address` |
| devices, settings, geolocation, files | **A** | platform LB `ip_address` |

- Start with **DNS-only** until you confirm HTTPS works.
- Then optional orange-cloud + SSL Full (strict).

HTTP port 80 on the LB redirects to HTTPS.

## Hydra public URLs

After `oauth2.stawi.org` serves Cloud Run Hydra:

```hcl
# apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars
advertise_public_hostname = true
```

Re-apply hydra so OIDC discovery advertises the public host.

## Cost note

Global external Application Load Balancer has a fixed base cost (~\$15–20/mo per forwarding rule setup) plus traffic.  
This replaces classic domain mapping (which is free but **unsupported in europe-west9**).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Domain mapping 501 in europe-west9 | Expected — use edge-lb-* apps |
| Certificate PROVISIONING | Missing/wrong DNS auth CNAME; use grey cloud |
| 502 from LB | Cloud Run service missing or wrong region/name in hosts map |
| 404 on host | URL map host rule missing or DNS still on old origin |

## Frame health

Frame: **`GET /healthz`**. Ory Hydra: `/health/ready`.
