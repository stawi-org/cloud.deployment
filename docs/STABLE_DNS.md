# Stable DNS contract (switchable backends)

Apps and clients should only use **hostnames we control**. Backends
(Cloud Run revisions, Worker origins) can change without env churn.

## Hostnames (prod)

| Hostname | Purpose | Edge | Backend switch via |
|----------|---------|------|--------------------|
| `api.stawi.org` | Product APIs + Scalar | CF Worker (orange) | `routes.prod.json` path origins |
| `accounts.stawi.org` | Login UI | CF orange CNAME → Cloud Run | `direct_cnames` origin |
| `oauth2.stawi.org` | OIDC public | CF orange CNAME → Cloud Run | `direct_cnames` origin |
| `oauth2-w.stawi.org` | Hydra **admin** (IAM) | CF orange CNAME → Cloud Run | `direct_cnames` origin |
| `authz.stawi.org` | Keto read gRPC (IAM) | CF orange CNAME → Cloud Run | `direct_cnames` origin |
| `authz-w.stawi.org` | Keto write gRPC (IAM) | CF orange CNAME → Cloud Run | `direct_cnames` origin |

**Do not put `*.run.app` in app env** except temporary break-glass. Runtime
config uses the table above (`modules/frame-cloudrun-app`).

## Architecture (no Google LB)

```
Client / S2S
    │
    ├─ https://api.stawi.org/<path>     → CF Worker → Cloud Run (path strip)
    │
    └─ https://oauth2*.stawi.org        → CF orange CNAME → *.a.run.app
       https://authz*.stawi.org           + Origin Rule: Host = run.app hostname
       https://accounts.stawi.org
```

Cloud Run routes by **Host**. A bare CNAME to `*.run.app` is not enough —
Cloudflare must rewrite the origin Host header (and optionally SNI) to the
Cloud Run service hostname. That is free on plans that allow Origin Rules
Host override; scripts:

- `edge/cloudflare-api-gateway/scripts/ensure-cf-dns.mjs`
- `edge/cloudflare-api-gateway/scripts/ensure-cf-origin-rules.mjs`
- HTTP fallback if Origin Rules 403: `ensure-cf-worker-host-fallback.mjs`

**Google Global HTTPS LB is not required** for oauth2*/authz*/accounts.
`edge-lb-identity` keeps `hosts = {}` so any leftover `edge-id` LB is destroyed
(~$18/mo saved). Re-add hosts there only if CF cannot rewrite Host for gRPC.

### Caveats

| Concern | Detail |
|---------|--------|
| gRPC (`authz*`) | Needs Origin Host rewrite (or CF gRPC proxy). Worker host-fallback is HTTP-oriented — prefer Origin Rules for Keto. |
| IAM | Callers still mint **Google ID tokens** (`roles/run.invoker`); audiences = stable HTTPS hosts via Cloud Run `custom_audiences`. |
| Switch backend | Change `origin` in `routes.prod.json` + re-run DNS/origin scripts (or re-deploy edge-api-gateway). App env stays on `*.stawi.org`. |

## Cost (minimal stable set)

| Piece | Role | Approx. |
|-------|------|---------|
| CF Worker + Universal SSL | `api` path hub only | free / ~$5 |
| CF orange CNAME + Origin Rules | `accounts`, `oauth2*`, `authz*` | free (plan permitting) |
| Google Global HTTPS LB | **retired** for identity | $0 |

## App env (S2S)

| Env | Value |
|-----|--------|
| `OAUTH2_SERVICE_URI` | `https://oauth2.stawi.org` |
| `OAUTH2_SERVICE_ADMIN_URI` | `https://oauth2-w.stawi.org` |
| `AUTHORIZATION_SERVICE_READ_URI` | `https://authz.stawi.org` |
| `AUTHORIZATION_SERVICE_WRITE_URI` | `https://authz-w.stawi.org` |
| Product `*_SERVICE_URI` | `https://api.stawi.org/<path>` |

## Ops

```bash
# Deploy CF edge (Worker + DNS + Origin Rules for all direct_cnames)
gh workflow run app-apply.yml -f app=edge-api-gateway -f env=stawi-prod
# or from edge/cloudflare-api-gateway:
#   npm run deploy:prod   # includes ensure-cf-dns / origin-rules / fallback

# Destroy idle identity LB (hosts={})
gh workflow run app-apply.yml -f app=edge-lb-identity -f env=stawi-prod
```

Break-glass only: point a single app env at `https://…a.run.app` if a stable
hostname is down — revert to `*.stawi.org` as soon as CF edge is healthy.
