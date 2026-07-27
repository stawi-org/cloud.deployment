# edge-lb-platform (retired product hosts)

Platform product APIs are **only** on `api.stawi.org`:

| Path | Service |
|------|---------|
| `/devices` | platform-devices |
| `/settings` | platform-settings |
| `/geolocation` | platform-geolocation |
| `/files` | platform-files |

See [`edge/cloudflare-api-gateway`](../../edge/cloudflare-api-gateway).

This OpenTofu app keeps `hosts = {}` so re-apply **destroys** the old Global LB +
`devices.stawi.org` / … DNS (saves ~$18/mo). Do not re-add product hosts here.
