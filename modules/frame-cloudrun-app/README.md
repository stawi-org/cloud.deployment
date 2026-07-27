# frame-cloudrun-app

Canonical **Frame** Cloud Run stack for identity / operations / platform apps.

**Not for:** `identity-oauth2-hydra`, `identity-authorization-keto`, or `edge-lb-*`.

## What it provisions

1. Hydra (+ optional Keto) data sources (same- or cross-project)
2. `edge-contract` env defaults
3. Runtime service account
4. Neon database (optional) + Secret Manager DB URLs
5. Shared `hydra-webhook-psk` accessor (when secret is not module-owned)
6. Pub/Sub Frame dual-URL messaging (default events topic, or custom topics)
7. Migrate Cloud Run job (`execute=false` by default)
8. Cloud Run service (h2c, public invoker, OAuth/Keto env, optional probes)
9. Optional keep-warm scheduler
10. Pub/Sub push OIDC IAM

## App root shape

```hcl
module "frame" {
  source = "../../../modules/frame-cloudrun-app"

  app_name   = var.app_name
  project_id = var.project_id
  region     = var.region
  platform   = var.platform
  image      = var.image
  labels     = var.labels

  identity_project_id = var.identity_project_id # null → this project
  identity_region     = var.identity_region

  neon_org_id     = var.neon_org_id
  neon_region_id  = var.neon_region_id
  neon_extensions = var.neon_extensions

  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  app_env                  = { /* app-only knobs */ }
}
```

App-local only:

- `generated_secrets.tf` when this app **owns** SM values
- Extra jobs (e.g. tenancy sync)
- Custom `messaging_topics` / `messaging_subscriptions` (trustage)
- `moved` blocks once when switching from hand-rolled modules

## Defaults (streamlined)

| Knob | Default |
|------|---------|
| `use_http2` | `true` |
| `public_invoker` | `true` |
| `min_instance_count` | `0` |
| `migrate_execute` | `false` |
| `disable_otel_exporters` | `true` |
| OAuth2 / Keto URIs (prod) | DNS: `oauth2`, `oauth2-w`, `authz`, `authz-w` `.stawi.org` |
| `KETO_SERVICE_ADMIN_URI` | Set when `enable_keto_admin` (→ `authz-w` in prod) |
| Neon extensions | base suite when DB enabled |
| Region | `europe-west1` |

## Escape hatches

- **Multi-topic:** `messaging_topics` + `messaging_subscriptions` + `push_oidc_audience`
- **Min instances:** `min_instance_count = 1` for in-process schedulers
- **Keep-warm:** `enable_keep_warm = true`, `startup_probe_path = "/healthz"`
- **Owned secrets:** `extra_secret_ids` / `extra_secret_values` + `grant_oauth_signer_accessor = false` if PSK is in that set
- **No DB:** `has_database = false`
