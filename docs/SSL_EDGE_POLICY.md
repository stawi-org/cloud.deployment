# SSL and edge policy (canonical)

**Goal:** best security + UX with low cost.  
**Region:** production Cloud Run is **`europe-west1`** (domain mapping supported).  
**Constraint (historical):** classic domain mapping was unavailable in `europe-west9` (501).

## Summary

| Hostname / surface | Client TLS | Edge | Origin | Cloudflare proxy |
|--------------------|------------|------|--------|------------------|
| **`api.stawi.org`** (product APIs + Scalar) | Cloudflare Universal SSL | **Worker path proxy only** | Cloud Run `*.run.app` | **Orange** |
| **`accounts.stawi.org`** (login UI) | CF Universal SSL **or** Google managed cert | Preferred: **Cloud Run domain mapping** + DNS records Google prints; interim: CF CNAME + Host rewrite | `identity-authentication` | Orange (CF path) or grey (native) |
| **`oauth2.stawi.org`** (OIDC public) | same | same | `identity-oauth2-hydra` | same |
| **`oauth2-w.stawi.org`** (Hydra admin) | same | same + IAM | `identity-oauth2-hydra-admin` | same |
| **`authz.stawi.org` / `authz-w`** (Keto) | same | same + IAM | keto read/write | same |

There are **no** product hosts (`profile.stawi.org`, `devices.*`, …) — only `api.stawi.org/<path>`.

## Why this split

### Cloudflare Worker — **api.stawi.org only**

- Path routing + Scalar multi-API hub  
- Does **not** front `oauth2` / `accounts` / control-plane hosts long-term  

### Control-plane + login hosts — prefer Cloud Run domain mapping

In **`europe-west1`**, map each FQDN with:

```bash
gcloud beta run domain-mappings create \
  --service=SERVICE --domain=FQDN --region=europe-west1 --project=PROJECT
```

Then install the **resourceRecords** Google returns (A/AAAA/CNAME) at Cloudflare.  
Cloud Run accepts `Host: FQDN` natively — **no Worker Host rewrite, no Google LB**.

Caveats (Google docs):

- Feature is **Preview**; Google still recommends Global HTTPS LB for some production cases  
- Cert provisioning can take minutes–hours  
- Verify `stawi.org` in Search Console first  
- For IAM services, keep `custom_audiences = ["https://FQDN"]`

### Interim (until domain mappings are ACTIVE)

- Orange **CNAME** → `*.run.app` + Origin Rule Host rewrite  
  (`ensure-cf-dns.mjs` + `ensure-cf-origin-rules.mjs`)  
- Free fallback: Worker host proxy (`ensure-cf-worker-host-fallback.mjs`)  
- Do **not** reintroduce Global LB unless domain mapping + CF both fail for gRPC

### Google Global HTTPS LB

- Optional fallback only (`edge-lb-identity` with non-empty `hosts`)  
- ~$18/mo; not required in `europe-west1` if domain mapping works  

## Zone SSL

Cloudflare zone mode: **Full (strict)** when origin presents a valid cert  
(Google-managed domain-mapping cert, or run.app cert behind Host rewrite).

See also: [docs/STABLE_DNS.md](./STABLE_DNS.md), [docs/REGION_MIGRATION_EUROPE_WEST1.md](./REGION_MIGRATION_EUROPE_WEST1.md).
