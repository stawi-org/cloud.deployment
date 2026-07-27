# Cloudflare DNS records for public edge

**Preferred:** managed by OpenTofu / Worker deploy  
(requires repo secret `CLOUDFLARE_API_TOKEN`). See [PUBLIC_EDGE_DNS.md](PUBLIC_EDGE_DNS.md)
and [SSL_EDGE_POLICY.md](SSL_EDGE_POLICY.md).

Do **not** hand-edit if automation owns them — re-run the edge workflows instead.

## Current policy (prod)

| Surface | DNS / proxy | How |
|---------|-------------|-----|
| `api.stawi.org` | Orange (proxied) | Worker path gateway + Scalar |
| `accounts.stawi.org` | Orange | Worker host route → login |
| `oauth2.stawi.org` | Orange | Worker host route → Hydra public |
| `oauth2-w`, `authz`, `authz-w` | Grey (DNS-only) | Google Cert Manager + `edge-lb-identity` |

**No product hosts** (`profile`, `devices`, `files`, … as zone records).  
Those services live only under `https://api.stawi.org/<path>`.

## Smoke after cutover

```bash
curl -sS https://api.stawi.org/_gateway/health
curl -sSI https://api.stawi.org/profile/healthz
curl -sSI https://api.stawi.org/devices/healthz
curl -sSI https://api.stawi.org/files/healthz
curl -sSI https://accounts.stawi.org/healthz
curl -sSI https://oauth2.stawi.org/health/ready
curl -sS https://oauth2.stawi.org/.well-known/openid-configuration | head -c 200
# Control plane — expect 403 without Google identity token
curl -sSI https://oauth2-w.stawi.org/health/ready
curl -sSI https://authz.stawi.org/health/ready
```

## Historical note

Early cutovers used per-service Google LB A records (`profile`, `devices`, …).
Those product hosts are **retired**. Do not re-add them; use the path gateway.
