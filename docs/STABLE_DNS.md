# Stable DNS contract (switchable backends)

Apps and clients should only use **hostnames we control**. Backends
(Cloud Run revisions, Worker origins) can change without env churn.

## Hostnames (prod)

| Hostname | Purpose | Edge | Backend switch via |
|----------|---------|------|--------------------|
| `api.stawi.org` | Product APIs + Scalar | CF Worker (orange) | `routes.prod.json` path origins |
| **`pay.stawi.org`** | Hosted checkout UI | **CF direct mapping** (Worker host proxy or Origin Host rewrite → `*.run.app`) | `host_routes` + `direct_cnames` (`checkout-checkout`) |
| `accounts.stawi.org` | Login UI | CF direct **or** optional domain-mapping overlay | `direct_cnames` / domain map |
| `oauth2.stawi.org` | OIDC public | same | same |
| `oauth2-w.stawi.org` | Hydra **admin** (IAM) | same | same |
| `authz.stawi.org` | Keto read gRPC (IAM) | same | same |
| `authz-w.stawi.org` | Keto write gRPC (IAM) | same | same |

**Do not put `*.run.app` in app env** except temporary break-glass. Runtime
config uses the table above (`modules/frame-cloudrun-app`).

## Architecture (CF direct mapping is first-class)

```
Client
    │
    ├─ https://api.stawi.org/<path>
    │     → CF Worker (Universal SSL) → Cloud Run *.run.app
    │
    ├─ https://pay.stawi.org/c/<session>
    │     → CF Universal SSL (orange)
    │     → Worker host_route (or Origin Rule) rewrites Host → run.app
    │     → checkout-checkout (no Google managed cert, no cert wait)
    │
    └─ https://accounts|oauth2*|authz*.stawi.org
          → same CF direct path by default
          ── optional grey CNAME → ghs.googlehosted.com (domain mapping) ──
```

### Why CF direct mapping (not Google domain-mapping certs) for pay

| Concern | Google domain mapping | CF direct (`direct_cnames`) |
|---------|----------------------|----------------------------|
| Client TLS | Google managed cert (minutes–hours; can stall) | **Cloudflare Universal SSL** (immediate) |
| Region | Only regions that support domain mapping (e.g. `europe-west1`) | **Any** Cloud Run region (`*.run.app`) |
| Host header | Native `Host: pay.stawi.org` | Origin Rule rewrites to `*.run.app` |
| Failure mode | 521/SSL while cert pending | Needs Origin Rules (or free Worker host fallback) |
| Checkout UX | Blocked during cert provisioning | Live as soon as DNS + rules apply |

We previously moved production to **`europe-west1`** partly to unlock Cloud Run domain
mapping. That feature remains **optional** for IAM hosts. **Hosted checkout must not
depend on it** — `pay.stawi.org` is **`edge: cf_direct` only**.

### Pipeline (edge-api-gateway deploy)

1. `ensure-cf-dns.mjs` — `api` + `host_routes` (pay) Worker dummy A; other `direct_cnames` orange CNAME → `*.run.app`
2. `ensure-cf-domain-mapping-dns.mjs` (optional) — greys **IAM** hosts only (`accounts`, `oauth2*`, `authz*`). **Never `pay`.**
3. `ensure-cf-origin-rules.mjs` — Host rewrite for pure CNAME directs when the token/plan allows  
   (exit 2 → Worker host fallback; **pay** is already a permanent `host_routes` entry)

**Production note:** Origin Rules API often returns 403 (token lacks Rulesets edit / plan).
`pay` is therefore a permanent Worker `host_route` + `wrangler` route `pay.stawi.org/*`
so Host rewrite never depends on Google certs or Origin Rules.

```bash
# Deploy CF edge
gh workflow run edge-api-gateway.yml
# or push under edge/cloudflare-api-gateway/**
```

Set `USE_DOMAIN_MAPPING_DNS=false` on the job to keep every direct host on pure CF path.

### Origin Host rewrite (required for CF direct)

Cloud Run only accepts `Host: <service>-….run.app` unless a domain mapping is
ACTIVE. Orange CNAME alone is not enough:

```
Client Host: pay.stawi.org
  → CF Origin Rule: host_header + origin host = checkout-checkout-….run.app
  → Cloud Run serves checkout HTML
```

Without the rule: Google frontend 404, or Cloudflare 521 if origin is unreachable.

## Caveats

| Concern | Detail |
|---------|--------|
| gRPC (`authz*`) | Needs Origin Host rewrite (or CF gRPC proxy). Worker host-fallback is HTTP-oriented — prefer Origin Rules for Keto. |
| IAM | Callers mint **Google ID tokens** (`roles/run.invoker`); audiences = stable HTTPS hosts via Cloud Run `custom_audiences`. |
| Switch backend | Change `origin` in `routes.prod.json` + re-run DNS/origin scripts (or re-deploy edge-api-gateway). App env stays on `*.stawi.org`. |
| Domain mapping | Optional IAM overlay only. Do not add `pay` to `DOMAIN_MAP_HOSTS` or `create-domain-mappings.sh`. |

## Cost (minimal stable set)

| Piece | Role | Approx. |
|-------|------|---------|
| CF Worker + Universal SSL | `api` path hub only | free / ~$5 |
| CF orange CNAME + Origin Rules | `pay`, `accounts`, `oauth2*`, `authz*` | free (plan permitting) |
| Worker host fallback | Free plan without Origin Host override | free |
| Google Global HTTPS LB | **retired** for identity | $0 |
| Google managed cert (domain mapping) | Optional IAM overlay | $0 + cert wait |

## App env (S2S)

| Env | Value |
|-----|--------|
| `OAUTH2_SERVICE_URI` | `https://oauth2.stawi.org` |
| `OAUTH2_SERVICE_ADMIN_URI` | `https://oauth2-w.stawi.org` |
| `AUTHORIZATION_SERVICE_READ_URI` | `https://authz.stawi.org` |
| `AUTHORIZATION_SERVICE_WRITE_URI` | `https://authz-w.stawi.org` |
| `CHECKOUT_PUBLIC_BASE_URL` | `https://pay.stawi.org` |
| Product `*_SERVICE_URI` | `https://api.stawi.org/<path>` |

## Ops

```bash
# Deploy CF edge (Worker + DNS + Origin Rules for all direct_cnames)
gh workflow run edge-api-gateway.yml

# Destroy idle identity LB (hosts={})
gh workflow run app-apply.yml -f app=edge-lb-identity -f env=stawi-prod
```

Break-glass only: point a single app env at `https://…a.run.app` if a stable
hostname is down — revert to `*.stawi.org` as soon as CF edge is healthy.
