# Cloudflare DNS records for public edge

**Preferred:** managed by `edge/cloudflare-api-gateway` ensure scripts  
(requires repo secret `CLOUDFLARE_API_TOKEN`). See [PUBLIC_EDGE_DNS.md](PUBLIC_EDGE_DNS.md)
and [SSL_EDGE_POLICY.md](SSL_EDGE_POLICY.md).

## Current policy (prod)

| Surface | DNS / proxy | How |
|---------|-------------|-----|
| `api.stawi.org` | Orange A → `192.0.2.1` | Worker path gateway + Scalar **only** |
| `accounts.stawi.org` | Orange CNAME → auth `*.run.app` | Direct origin + Origin Rule Host rewrite |
| `oauth2.stawi.org` | Orange CNAME → hydra `*.run.app` | Direct origin + Origin Rule Host rewrite |
| `oauth2-w`, `authz`, `authz-w` | Grey A → Google LB | `edge-lb-identity` |

## Smoke

```bash
curl -sS https://api.stawi.org/_gateway/health
# These must NOT return x-stawi-gateway
curl -sSI https://accounts.stawi.org/readyz
curl -sSI https://oauth2.stawi.org/health/ready
curl -sSI https://oauth2-w.stawi.org/health/ready
```
