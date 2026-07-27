# SSL and edge policy (canonical)

**Goal:** best security + UX with low cost.  
**Constraint:** Cloud Run domain mapping is unavailable in `europe-west9`.

## Summary

| Hostname / surface | Client TLS | Edge | Origin | Cloudflare proxy |
|--------------------|------------|------|--------|------------------|
| **`api.stawi.org`** (product APIs + Scalar) | Cloudflare Universal SSL | **Worker path proxy only** | Cloud Run `*.run.app` | **Orange** |
| **`accounts.stawi.org`** (login UI) | Cloudflare Universal SSL | **DNS CNAME → run.app** (no Worker, no Google LB) | `identity-authentication` | **Orange** |
| **`oauth2.stawi.org`** (OIDC public) | Cloudflare Universal SSL | **DNS CNAME → run.app** (no Worker, no Google LB) | `identity-oauth2-hydra` | **Orange** |
| **`oauth2-w.stawi.org`** (Hydra admin) | Google Certificate Manager | Global HTTPS LB + NEG | Cloud Run (IAM) | **Grey** |
| **`authz.stawi.org` / `authz-w`** (Keto) | Google Certificate Manager | Global HTTPS LB + NEG | Cloud Run (IAM) | **Grey** |

There are **no** product hosts (`profile.stawi.org`, `devices.*`, …).

## Why this split

### Cloudflare Worker — **api.stawi.org only**

- Path routing + Scalar multi-API hub  
- Does **not** front `oauth2` / `accounts`  

### Cloudflare DNS (orange) — login + OIDC public (**no Google LB**)

Preferred (needs CF Rulesets permission + Host-header Origin Rule capability):

- Orange **CNAME** `accounts` / `oauth2` → Cloud Run `*.run.app`  
- **Origin Rule** sets `Host` to that run.app hostname  
- Managed by `ensure-cf-dns.mjs` + `ensure-cf-origin-rules.mjs`  

Free fallback when Origin Rules are unavailable (token/plan):

- Same public hostnames; **Worker host proxy** rewrites to run.app (not path API routing)  
- `ensure-cf-worker-host-fallback.mjs` — still **no Google LB**  

### Google Certificate Manager (grey) — control plane only

- `oauth2-w` + `authz*` remain IAM-authenticated  
- OpenTofu `edge-lb-identity` owns A + ACME CNAMEs  
- **proxied = false**  

## Implementation map

| Component | Role |
|-----------|------|
| [`edge/cloudflare-api-gateway`](../edge/cloudflare-api-gateway) | Worker **api only** + DNS ensure for api + direct CNAMEs + origin Host rules |
| [`apps/edge-lb-identity`](../apps/edge-lb-identity) | Google LB for **oauth2-w, authz, authz-w only** |
| [`config/public-edge.yaml`](../config/public-edge.yaml) | Registry |

## Operator cutover

```bash
gh workflow run edge-api-gateway.yml
gh workflow run app-apply.yml -f app=edge-lb-identity -f env=stawi-prod
```

Smoke:

```bash
# Worker
curl -sS https://api.stawi.org/_gateway/health
# Must NOT include x-stawi-gateway
curl -sSI https://accounts.stawi.org/readyz
curl -sSI https://oauth2.stawi.org/health/ready
# Control plane grey — 403 without Google identity token
curl -sSI https://oauth2-w.stawi.org/health/ready
```

## Notes

- **Origin Host rewrite** may require a Cloudflare plan that includes Origin Rule *Host header* override. If `ensure-cf-origin-rules.mjs` fails, expand the API token / plan (see CF Origin Rules docs) — do not put accounts/oauth2 back on the api Worker or Google LB unless product decides otherwise.  
- Zone SSL mode: **Full (strict)**.  
