# Cloudflare DNS records for Cloud Run public edge

**Preferred:** managed by OpenTofu in `edge-lb-identity` / `edge-lb-platform`  
(requires repo secret `CLOUDFLARE_API_TOKEN`). See [PUBLIC_EDGE_DNS.md](PUBLIC_EDGE_DNS.md).

The tables below are the **expected** records (for debugging / one-time import).  
Do **not** hand-edit if OpenTofu owns them — re-apply the edge-lb apps instead.

---

Historical snapshot after first LB apply (2026-07-25).

## 1) Certificate validation CNAMEs (add first)

| Name (Cloudflare) | Type | Content | Proxy |
|-------------------|------|---------|-------|
| `_acme-challenge.accounts` | CNAME | `88ade752-4d66-4ef5-a7af-8b537209f701.13.authorize.certificatemanager.goog` | DNS only |
| `_acme-challenge.oauth2` | CNAME | `a44030d5-56a4-4344-934a-06f34ec54cca.17.authorize.certificatemanager.goog` | DNS only |
| `_acme-challenge.profile` | CNAME | `c5a7a4f3-cede-4b32-a572-a733bac4d08d.4.authorize.certificatemanager.goog` | DNS only |
| `_acme-challenge.tenancy` | CNAME | `ea06b012-f9e6-4c65-aadf-8a5d4c888931.18.authorize.certificatemanager.goog` | DNS only |
| `_acme-challenge.identity` | CNAME | `f650c623-0967-4367-b6cb-2f80673d2e72.12.authorize.certificatemanager.goog` | DNS only |
| `_acme-challenge.devices` | CNAME | `fceb1dce-7f7d-4877-bf16-be93e2038404.13.authorize.certificatemanager.goog` | DNS only |
| `_acme-challenge.settings` | CNAME | `77274882-466e-45d1-998e-2f728360ca2a.17.authorize.certificatemanager.goog` | DNS only |
| `_acme-challenge.geolocation` | CNAME | `a09b0ba3-3dbc-42cc-a38e-66719152a39f.4.authorize.certificatemanager.goog` | DNS only |
| `_acme-challenge.files` | CNAME | `74664da4-12b2-4ff5-8497-c29ecdb0f01c.13.authorize.certificatemanager.goog` | DNS only |

Omit trailing dots in the Cloudflare UI if it auto-appends the zone.

Check certs:

```bash
gcloud certificate-manager certificates list --project=stawi-identity --location=global
gcloud certificate-manager certificates list --project=stawi-platform --location=global
# want STATE=ACTIVE
```

## 2) Traffic A records (after certs Active — or in parallel if you accept brief TLS errors)

### Identity LB — `34.50.159.182`

| Name | Type | Content | Proxy (initially) |
|------|------|---------|-------------------|
| `accounts` | A | `34.50.159.182` | DNS only |
| `oauth2` | A | `34.50.159.182` | DNS only |
| `profile` | A | `34.50.159.182` | DNS only |
| `tenancy` | A | `34.50.159.182` | DNS only |
| `identity` | A | `34.50.159.182` | DNS only |

### Platform LB — `136.69.29.183`

| Name | Type | Content | Proxy (initially) |
|------|------|---------|-------------------|
| `devices` | A | `136.69.29.183` | DNS only |
| `settings` | A | `136.69.29.183` | DNS only |
| `geolocation` | A | `136.69.29.183` | DNS only |
| `files` | A | `136.69.29.183` | DNS only |

## 3) Smoke after cutover

```bash
curl -sSI https://oauth2.stawi.org/health/ready
curl -sS https://oauth2.stawi.org/.well-known/openid-configuration | head -c 200
curl -sSI https://accounts.stawi.org/healthz
curl -sSI https://profile.stawi.org/healthz
curl -sSI https://devices.stawi.org/healthz
```

Then set Hydra `advertise_public_hostname = true` and re-apply.

## Note

Classic Cloud Run domain mapping returns **501** in `europe-west9`.  
These LBs are the supported replacement (`apps/edge-lb-identity`, `apps/edge-lb-platform`).
