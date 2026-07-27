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

## Architecture (prefer domain mapping in `europe-west1`)

```
Client / S2S
    │
    ├─ https://api.stawi.org/<path>     → CF Worker → Cloud Run (path strip)
    │
    └─ https://oauth2*.stawi.org        → Cloud Run domain mapping (preferred)
       https://authz*.stawi.org           DNS records from `gcloud beta run domain-mappings`
       https://accounts.stawi.org
                                      ── or interim CF CNAME + Host rewrite ──
```

**Preferred:** map FQDNs with Cloud Run domain mapping (`scripts/create-domain-mappings.sh`).
Cloud Run then accepts `Host: oauth2-w.stawi.org` natively — no Worker, no Google LB.

**Interim** (before mappings ACTIVE): orange CNAME → `*.run.app` + Origin Host rewrite
(`ensure-cf-dns.mjs` / `ensure-cf-origin-rules.mjs` / Worker host fallback).

**Google Global HTTPS LB** is break-glass only (`edge-lb-identity` hosts non-empty).

Region migration: [REGION_MIGRATION_EUROPE_WEST1.md](./REGION_MIGRATION_EUROPE_WEST1.md).

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
