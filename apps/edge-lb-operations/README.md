# edge-lb-operations

OpenTofu-owned edge for operations hostnames:

- Global HTTPS LB + serverless NEGs → Cloud Run
- Certificate Manager (Google-managed TLS)
- Cloudflare DNS (`A` + ACME `CNAME`) via provider token

Classic Cloud Run domain mapping is **not** available in `europe-west9`.

| Host | Backend Cloud Run |
|------|-------------------|
| audit.stawi.org | operations-audit |
| formstore.stawi.org | operations-formstore |
| queuestore.stawi.org | operations-queuestore |
| redirect.stawi.org | operations-redirect |
| thesa.stawi.org | operations-thesa |
| trustage.stawi.org | operations-trustage |

Requires repo secret `CLOUDFLARE_API_TOKEN`. See [docs/PUBLIC_EDGE_DNS.md](../../docs/PUBLIC_EDGE_DNS.md).
