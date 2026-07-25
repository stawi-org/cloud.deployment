# edge-lb-platform

OpenTofu-owned public edge for platform hostnames:

- Global HTTPS LB + serverless NEGs → Cloud Run
- Certificate Manager (Google-managed TLS)
- Cloudflare DNS (`A` + ACME `CNAME`) via provider token

| Host | Backend Cloud Run |
|------|-------------------|
| devices.stawi.org | platform-devices |
| settings.stawi.org | platform-settings |
| geolocation.stawi.org | platform-geolocation |
| files.stawi.org | platform-files |

Requires repo secret `CLOUDFLARE_API_TOKEN`. See [docs/PUBLIC_EDGE_DNS.md](../../docs/PUBLIC_EDGE_DNS.md).