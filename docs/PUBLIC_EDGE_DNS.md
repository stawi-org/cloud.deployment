# Public edge DNS → Cloud Run (host per service)

Each migrated Cloud Run service gets its **own hostname** on `stawi.org`.  
There is **no** Cloud Run path router / edge proxy.

**Registry:** [`config/public-edge.yaml`](../config/public-edge.yaml)  
**DNS today:** Cloudflare (orange-cloud on stawi.org).  
**Create mappings:** [`scripts/create-domain-mappings.sh`](../scripts/create-domain-mappings.sh) (**user gcloud**, not CI)

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

If those URLs must keep working, implement **Cloudflare** routing to the hosts above — not a Cloud Run edge service.

```text
api.stawi.org/devices/*  →  devices.stawi.org/*
api.stawi.org/profile/*  →  profile.stawi.org/*
```

## Why CI does not create mappings

Domain mappings must be created by a **Google user** that owns the Search Console
property for `stawi.org`. The CI identity `tofu-deploy@…` is a service account and
will fail with “domain not verified”.

OpenTofu keeps `enable_domain_mapping = false`. Use the **local user script** instead.

## Step-by-step

### 1. Confirm verification for *this* gcloud user

```bash
gcloud config get-value account    # e.g. bwire@stawi.org
gcloud domains list-user-verified # must include stawi.org
```

Apex DNS **already** has:

```text
google-site-verification=zSyjIq6uWNhB12YRZoPhiAYfOrGYafeEuldX6Sn7Ttg
```

If `list-user-verified` is **empty**, ownership is not attached to this login yet:

1. Open [Search Console](https://search.google.com/search-console) as **the same account** as gcloud.
2. Add property → **Domain** → `stawi.org` (not URL-prefix).
3. Click **Verify** (TXT is already published — should succeed immediately).
4. Or: Settings → Users and permissions → add this account as **Owner** if another user already verified.
5. Re-check: `gcloud domains list-user-verified`

Also: `gcloud domains verify stawi.org` only opens Search Console; you must finish Verify there.

### 2. Create all domain mappings

```bash
./scripts/create-domain-mappings.sh
./scripts/create-domain-mappings.sh --describe
```

### 3. Cloudflare DNS

For each hostname, add the `resourceRecords` Google prints (usually CNAME → `ghs.googlehosted.com`).

| Tip | Detail |
|-----|--------|
| Certificate issuance | Use **DNS-only (grey cloud)** until status Active |
| After Active | Optional orange-cloud + SSL Full (strict) |

### 4. Hydra public URLs

After `oauth2.stawi.org` is Active and DNS points at Cloud Run:

```hcl
# apps/identity-oauth2-hydra/cloudrun/envs/stawi-prod.tfvars
advertise_public_hostname = true
```

Re-apply hydra so OIDC discovery advertises the public host.

### 5. Clients / k8s retirement

Point apps and browsers at the new hosts (or CF path aliases). Then remove K8s Gateway routes for cut-over hosts in `deployment.manifests`.

## OpenTofu knobs (inventory only)

| Variable | Purpose |
|----------|---------|
| `public_hostname` | FQDN for this service (set in each app tfvars) |
| `enable_domain_mapping` | **Keep false** for CI; use create-domain-mappings.sh |
| `advertise_public_hostname` | Hydra only — public OIDC URLs after DNS cutover |

## Frame health

Frame default: **`GET /healthz`**. Ory: `/health/ready`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| “You currently have no verified domains” | Finish Search Console Domain verify as **this** gcloud user |
| TXT present but still not verified | Wrong SC property type (use Domain) or different Google account |
| CI apply fails on domain mapping | Expected if enabled — use user script; leave flag false |
| CertificatePending | Grey-cloud CNAME to Google target until Active |
| Hydra still shows `*.run.app` | `advertise_public_hostname = true` after oauth2 cutover |
