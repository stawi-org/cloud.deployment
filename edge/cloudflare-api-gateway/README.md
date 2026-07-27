# Cloudflare public edge (`stawi-api-gateway`)

Implements [docs/SSL_EDGE_POLICY.md](../../docs/SSL_EDGE_POLICY.md): **Cloudflare Universal SSL**
for **`api.stawi.org` only** (Worker). Origins are always Cloud Run `*.run.app`.

```
https://api.stawi.org/            →  Scalar hub
https://api.stawi.org/profile/…   →  path proxy → identity-profile
```

`accounts.stawi.org` / `oauth2.stawi.org` are **not** on this Worker and **not** on
the Google LB. Deploy also ensures orange **CNAME → `*.run.app`** plus Origin Rule
Host rewrite (`scripts/ensure-cf-dns.mjs`, `ensure-cf-origin-rules.mjs`).

## Scalar hub

The hub is generated from `routes[].docs` in [`config/routes.prod.json`](./config/routes.prod.json).

| Field | Purpose |
|-------|---------|
| `docs.enabled` | Include in Scalar document switcher |
| `docs.title` | Label in the hub |
| `docs.openapi_path` | Path on the **service** (default `/openapi.yaml`) after prefix strip |
| `docs.default` | Default document when the hub loads |
| `docs.description` | Optional blurb |

Scalar loads each spec from the **gateway** URL:

`https://api.stawi.org{prefix}{openapi_path}`  
e.g. `https://api.stawi.org/profile/openapi.yaml`

The Worker rewrites the OpenAPI `servers` entry to  
`https://api.stawi.org{prefix}` so **Try it** and code samples hit the path gateway
(Connect paths like `/profile.v1.ProfileService/Create` stay relative to that base).

Services that do not expose OpenAPI yet still appear if `docs.enabled: true`; Scalar
will show a load error for that document until the service serves the path.
Set `docs.enabled: false` to hide them.

## Extend (add a service)

1. Deploy the Cloud Run service as usual (`apps/<name>`).
2. Serve OpenAPI on the service (Frame: `/openapi.yaml` or `/debug/frame/openapi/{name}`).
3. Append one object to [`config/routes.prod.json`](./config/routes.prod.json):

```json
{
  "id": "payment",
  "prefix": "/payment",
  "service": "payments-payment",
  "project": "stawi-payments",
  "origin": "https://payments-payment-xxxxx-od.a.run.app",
  "strip_prefix": true,
  "enabled": true,
  "public": true,
  "docs": {
    "enabled": true,
    "title": "Payment",
    "description": "Checkout and payment intents.",
    "openapi_path": "/openapi.yaml"
  }
}
```

4. Prefer live origins:

```bash
npm run refresh-origins   # needs gcloud auth on domain projects
npm run validate && npm test
npm run deploy            # CLOUDFLARE_API_TOKEN required
```

5. Smoke:

```bash
curl -sS https://api.stawi.org/_gateway/health
curl -sS https://api.stawi.org/_gateway/docs | head
curl -sSI https://api.stawi.org/docs
curl -sSI https://api.stawi.org/payment/
curl -sS https://api.stawi.org/payment/openapi.yaml | head
```

**Rules**

| Rule | Why |
|------|-----|
| `prefix` starts with `/`, not bare `/` | Prevents catch-all open routing |
| `origin` must be `https://*.run.app` only | No product `*.stawi.org` hosts — path gateway only |
| Longest prefix wins | Safe nested paths later |
| `strip_prefix: true` (default) | Service keeps handlers at `/` (Connect: `/profile.v1…`) |
| `docs.openapi_path` on the service root | After strip, gateway fetches that path from Cloud Run |

## Safety

- **Not an open proxy** — origins are config-only; re-checked at runtime.
- **Host header** forced to the Cloud Run / origin host.
- **Hop-by-hop headers** stripped; `X-Forwarded-Host=api.stawi.org` set for apps.
- **Path escape** after strip is normalized.
- **Unknown paths** → JSON 404 from the gateway (no silent default backend).
- **Authenticated services** (`public: false`, e.g. tenancy) still enforce Cloud Run IAM; the gateway only forwards headers/tokens.

## Cost

| Plan | Limit | Notes |
|------|--------|--------|
| Workers **Free** | 100k req/day | Enough to start |
| Workers **Paid** (~$5/mo) | Millions + $0.30/M | Still far below a GCP Global LB (~$18/mo) |

Cloud Run usage is billed separately either way.

## Deploy

### Token scopes

Create an API token (or extend `CLOUDFLARE_API_TOKEN`) with:

- Account → **Workers Scripts:Edit**
- Zone (stawi.org) → **Workers Routes:Edit**
- Zone → **DNS:Read** (wrangler zone_name lookup)

DNS-only tokens used for OpenTofu edge-lb will **not** deploy Workers.

### Local

```bash
export CLOUDFLARE_API_TOKEN=…
# optional if auto-detect fails:
# export CLOUDFLARE_ACCOUNT_ID=…

cd edge/cloudflare-api-gateway
npm install
./scripts/deploy.sh
npm run smoke
```

### CI

Workflow: [`.github/workflows/edge-api-gateway.yml`](../../.github/workflows/edge-api-gateway.yml)

```bash
gh workflow run edge-api-gateway.yml
```

## Ops endpoints

| Path | Purpose |
|------|---------|
| `GET /` or `/docs` | **Scalar multi-API hub** (HTML) |
| `GET /_gateway/health` | Liveness JSON |
| `GET /_gateway/routes` | Registered prefixes (no secrets) |
| `GET /_gateway/docs` | Docs catalog JSON (Scalar sources + openapi URLs) |
| `GET /{prefix}/openapi.yaml` | Proxied OpenAPI with gateway `servers` rewrite |

## Relation to GCP `apps/api-gateway`

| | Cloudflare Worker (this) | `apps/api-gateway` (GCP LB) |
|--|--------------------------|-------------------------------|
| Cost | Free / ~$5 | ~$18+/mo fixed |
| Default | **Yes** | Optional premium edge |
| Apply | `wrangler deploy` / GH workflow | OpenTofu |

Prefer **this** path for production cost control. Keep the GCP module only if you later need Google-native Armor/cert centralization.

## DNS note

`api.stawi.org` should remain **proxied (orange cloud)** on Cloudflare so the Worker route can serve traffic even when no GCP origin IP is healthy. The Worker handles requests at the edge; a dead origin A record no longer causes 521 once the route is attached.
