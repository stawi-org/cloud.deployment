# edge-lb-operations (retired product hosts)

Operations product APIs are **only** on `api.stawi.org`:

| Path | Service |
|------|---------|
| `/audit` | operations-audit |
| `/formstore` | operations-formstore |
| `/queuestore` | operations-queuestore |
| `/redirect` | operations-redirect |
| `/thesa` | operations-thesa |
| `/trustage` | operations-trustage |

See [`edge/cloudflare-api-gateway`](../../edge/cloudflare-api-gateway).

This OpenTofu app keeps `hosts = {}` so re-apply **destroys** the old Global LB +
product host DNS. Do not re-add product hosts here.

Operations routes on the Worker need `*.run.app` origins — run
`npm run refresh-origins` with access to `stawi-operations`, then enable routes.
