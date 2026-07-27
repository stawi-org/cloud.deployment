# SSL and edge policy (canonical)

**Goal:** best security + UX with low cost.  
**Constraint:** Cloud Run domain mapping is unavailable in `europe-west9`.

## Summary

| Hostname / surface | Client TLS | Edge | Origin | Cloudflare proxy |
|--------------------|------------|------|--------|------------------|
| **`api.stawi.org`** (product APIs + Scalar) | Cloudflare Universal SSL | **Worker path proxy only** | Cloud Run `*.run.app` | **Orange** |
| **`accounts.stawi.org`** (login UI) | Google Certificate Manager | Global HTTPS LB + NEG | `identity-authentication` | **Grey** |
| **`oauth2.stawi.org`** (OIDC public) | Google Certificate Manager | Global HTTPS LB + NEG | `identity-oauth2-hydra` | **Grey** |
| **`oauth2-w.stawi.org`** (Hydra admin) | Google Certificate Manager | Global HTTPS LB + NEG | Cloud Run (IAM) | **Grey** |
| **`authz.stawi.org` / `authz-w`** (Keto) | Google Certificate Manager | Global HTTPS LB + NEG | Cloud Run (IAM) | **Grey** |

There are **no** product hosts (`profile.stawi.org`, `devices.*`, …).

## Why this split

### Cloudflare Worker (orange) — **api.stawi.org only**

- Path routing + Scalar multi-API hub without a second GCP Global LB  
- Does **not** front `oauth2` / `accounts` (those stay on Google TLS end-to-end)  
- Origin is always HTTPS `*.run.app` with Google-managed certs  

**Zone SSL/TLS mode must be Full (strict)** — never Flexible.

### Google Certificate Manager (grey) — OIDC, login, control plane

- Client TLS terminates on Google GFEs only (no Cloudflare MITM)  
- `accounts` + `oauth2` public apps (`allUsers` invoker)  
- `oauth2-w` + `authz*` remain IAM-authenticated  
- OpenTofu owns A + `_acme-challenge` CNAMEs via `edge-lb-identity`  
- Keep **proxied = false** on these DNS records  

## Implementation map

| Component | Role |
|-----------|------|
| [`edge/cloudflare-api-gateway`](../edge/cloudflare-api-gateway) | Worker: **`api.stawi.org` only** — path routes + Scalar |
| [`apps/edge-lb-identity`](../apps/edge-lb-identity) | Google LB + Cert Manager for **accounts, oauth2, oauth2-w, authz, authz-w** |
| [`apps/edge-lb-platform`](../apps/edge-lb-platform) / [`operations`](../apps/edge-lb-operations) | **Retired** (`hosts = {}`) |
| [`config/public-edge.yaml`](../config/public-edge.yaml) | Registry of this policy |

## Operator cutover order

1. **Expand** `CLOUDFLARE_API_TOKEN` (Workers Scripts:Edit + Workers Routes:Edit + DNS Edit).  
2. **Deploy Worker** (api only): `gh workflow run edge-api-gateway.yml`  
3. Confirm orange-cloud DNS for **`api` only**.  
4. **Apply** `edge-lb-identity` (accounts + oauth2 + control plane, grey).  
5. Confirm grey A records for `accounts`, `oauth2`, `oauth2-w`, `authz*`.  
6. Cloudflare dashboard → SSL/TLS → **Full (strict)** for zone `stawi.org`.  
7. Smoke:

```bash
curl -sS https://api.stawi.org/_gateway/health
curl -sSI https://api.stawi.org/docs
curl -sSI https://accounts.stawi.org/readyz
curl -sSI https://oauth2.stawi.org/health/ready
# Control plane — expect 403 without Google identity token
curl -sSI https://oauth2-w.stawi.org/health/ready
curl -sSI https://authz.stawi.org/health/ready
```

## Security checklist

- [ ] Zone SSL mode **Full (strict)**  
- [ ] No Flexible SSL  
- [ ] Worker routes **only** `api.stawi.org/*`  
- [ ] `accounts` / `oauth2` / control-plane hosts **grey-cloud** only  
- [ ] Product origins only `https://*.run.app` (validated in Worker + `npm run validate`)  
- [ ] ACME / traffic DNS for Google LB owned by OpenTofu (no hand edits)  
- [ ] Tokens: Workers scopes for gateway deploy; DNS Edit for edge-lb ACME  

## Server-side (Cloud Run → APIs)

Apps call **stable public hostnames**, not `*.run.app` (run.app is edge origin only).

### Product APIs — path gateway

| Env | Value |
|-----|--------|
| `PROFILE_SERVICE_URI` | `https://api.stawi.org/profile` |
| `TENANCY_SERVICE_URI` | `https://api.stawi.org/tenancy` |
| `DEVICE_SERVICE_URI` | `https://api.stawi.org/devices` |
| `FILES_SERVICE_URI` | `https://api.stawi.org/files` |
| `PERMISSIONS_REGISTRATION_URL` | `https://api.stawi.org/tenancy/_internal/register/permissions` |
| `OAUTH2_RESOURCE_AUDIENCE` / requested audiences | `https://api.stawi.org/<path>` |

### Hydra / Keto — dedicated hosts

| Env | Value |
|-----|--------|
| `OAUTH2_SERVICE_URI` / Hydra public internal | `https://oauth2.stawi.org` |
| `OAUTH2_SERVICE_ADMIN_URI` | `https://oauth2-w.stawi.org` |
| `OAUTH2_CLIENT_ASSERTION_AUDIENCE` | `https://oauth2.stawi.org/oauth2/token` |
| `AUTHORIZATION_SERVICE_READ_URI` | `https://authz.stawi.org` |
| `AUTHORIZATION_SERVICE_WRITE_URI` / `KETO_SERVICE_ADMIN_URI` | `https://authz-w.stawi.org` |

Wired in `modules/frame-cloudrun-app`.

**Do not** use retired product hosts (`profile.stawi.org`, …) or app-level
`*.run.app` URLs for product HTTP.

## Cost

| Piece | Approx. |
|-------|---------|
| Cloudflare Universal SSL + Worker (free tier / ~$5 paid) | `api.stawi.org` path hub only |
| One Global LB (`edge-lb-identity`) | ~$18/mo (accounts + oauth2 + control plane) |
| Retired platform/ops host LBs | $0 after destroy |

## Out of scope

- Cloud Run domain mapping (unavailable in region)  
- Hand-managed Let’s Encrypt on VMs  
- Orange-cloud on Keto / Hydra admin / accounts / oauth2  
