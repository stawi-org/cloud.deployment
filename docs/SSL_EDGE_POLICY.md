# SSL and edge policy (canonical)

**Goal:** best security + UX with low cost — **no wait on Google managed certs for
browser checkout**.  
**Region:** production Cloud Run defaults to **`europe-west1`**. CF direct mapping
works in **any** region; domain mapping does not.

## Summary

| Hostname / surface | Client TLS | Edge | Origin | Cloudflare proxy |
|--------------------|------------|------|--------|------------------|
| **`api.stawi.org`** (product APIs + Scalar) | Cloudflare Universal SSL | **Worker path proxy only** | Cloud Run `*.run.app` | **Orange** |
| **`pay.stawi.org`** (hosted checkout) | **CF Universal SSL** | **CF direct mapping** (Worker `host_routes` Host rewrite → run.app; Origin Rules optional) | `checkout-checkout` | **Orange** |
| **`accounts.stawi.org`** (login UI) | CF Universal SSL **or** Google managed cert | CF direct default; optional domain-mapping DNS overlay | `identity-authentication` | Orange (CF) or grey (native) |
| **`oauth2.stawi.org`** (OIDC public) | same | same | `identity-oauth2-hydra` | same |
| **`oauth2-w.stawi.org`** (Hydra admin) | same | same + IAM | `identity-oauth2-hydra-admin` | same |
| **`authz.stawi.org` / `authz-w`** (Keto) | same | same + IAM | keto read/write | same |

There are **no** product hosts (`profile.stawi.org`, `devices.*`, …) — only `api.stawi.org/<path>`.

## Why this split

### Cloudflare Worker — **api.stawi.org only**

- Path routing + Scalar multi-API hub  
- Does **not** front `pay` / `oauth2` / `accounts` long-term  

### Browser + control-plane hosts — **CF direct mapping first**

```
Client TLS: Cloudflare Universal SSL (immediate)
DNS:        orange CNAME → <service>-….run.app
Origin:     Origin Rule rewrites Host + origin host to that run.app name
SSL mode:   Full (strict) — origin presents Google’s run.app cert
```

Implemented by:

- `direct_cnames` in `edge/cloudflare-api-gateway/config/routes.prod.json`
- `scripts/ensure-cf-dns.mjs`
- `scripts/ensure-cf-origin-rules.mjs` (always on deploy)
- Free fallback: `scripts/ensure-cf-worker-host-fallback.mjs` (skips domain-mapped hosts)

**`pay.stawi.org` is CF direct only** (`edge: cf_direct`). Do not create a Cloud Run
domain mapping for pay and do not add `pay` to `DOMAIN_MAP_HOSTS`.

### Optional: Cloud Run domain mapping (IAM overlay)

In regions that support it (e.g. **`europe-west1`**):

```bash
gcloud beta run domain-mappings create \
  --service=SERVICE --domain=FQDN --region=europe-west1 --project=PROJECT
```

Then grey CNAME → `ghs.googlehosted.com` via `ensure-cf-domain-mapping-dns.mjs`.

Caveats:

- Feature is **Preview** and **region-gated** (historically 501 in `europe-west9`)
- Cert provisioning can take **minutes–hours** and blocks HTTPS until Ready
- Suitable as an optional IAM overlay — **not** for checkout UX

Region migration context: [REGION_MIGRATION_EUROPE_WEST1.md](./REGION_MIGRATION_EUROPE_WEST1.md).  
The region move unlocked domain mapping; **checkout must not depend on that feature**.

### Google Global HTTPS LB

- Optional fallback only (`edge-lb-identity` with non-empty `hosts`)  
- ~$18/mo; not required when CF direct mapping works  

## Zone SSL

Cloudflare zone mode: **Full (strict)**  

| Path | Origin cert |
|------|-------------|
| CF direct (Host rewrite to `*.run.app`) | Google-managed **run.app** cert |
| Domain mapping (grey → ghs) | Google-managed **custom domain** cert |

See also: [docs/STABLE_DNS.md](./STABLE_DNS.md).
