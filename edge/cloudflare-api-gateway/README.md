# Cloudflare API gateway (`api.stawi.org`)

Low-cost **path proxy** in front of multi-project Cloud Run services.

```
https://api.stawi.org/profile/…  →  identity-profile (Cloud Run)
https://api.stawi.org/devices/…  →  platform-devices
…
```

No GCP Global Load Balancer. Cloudflare terminates TLS and routes by path prefix
(same product convention as the K8s Gateway HTTPRoutes).

## Extend (add a service)

1. Deploy the Cloud Run service as usual (`apps/<name>`).
2. Append one object to [`config/routes.prod.json`](./config/routes.prod.json):

```json
{
  "id": "payment",
  "prefix": "/payment",
  "service": "payments-payment",
  "project": "stawi-payments",
  "origin": "https://payments-payment-xxxxx-od.a.run.app",
  "strip_prefix": true,
  "enabled": true,
  "public": true
}
```

3. Prefer live origins:

```bash
npm run refresh-origins   # needs gcloud auth on domain projects
npm run validate && npm test
npm run deploy            # CLOUDFLARE_API_TOKEN required
```

4. Smoke:

```bash
curl -sS https://api.stawi.org/_gateway/health
curl -sSI https://api.stawi.org/payment/
```

**Rules**

| Rule | Why |
|------|-----|
| `prefix` starts with `/`, not bare `/` | Prevents catch-all open routing |
| `origin` must be `https` and allowlisted (`*.run.app` or known `*.stawi.org` hosts) | Blocks open-proxy footguns |
| Longest prefix wins | Safe nested paths later |
| `strip_prefix: true` (default) | Service keeps handlers at `/` (Connect: `/profile.v1…`) |

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
| `GET /_gateway/health` | Liveness JSON |
| `GET /_gateway/routes` | Registered prefixes (no secrets) |

## Relation to GCP `apps/api-gateway`

| | Cloudflare Worker (this) | `apps/api-gateway` (GCP LB) |
|--|--------------------------|-------------------------------|
| Cost | Free / ~$5 | ~$18+/mo fixed |
| Default | **Yes** | Optional premium edge |
| Apply | `wrangler deploy` / GH workflow | OpenTofu |

Prefer **this** path for production cost control. Keep the GCP module only if you later need Google-native Armor/cert centralization.

## DNS note

`api.stawi.org` should remain **proxied (orange cloud)** on Cloudflare so the Worker route can serve traffic even when no GCP origin IP is healthy. The Worker handles requests at the edge; a dead origin A record no longer causes 521 once the route is attached.
