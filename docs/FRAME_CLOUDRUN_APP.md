# Frame Cloud Run apps (canonical)

All **Frame** services (identity / operations / platform) deploy through
[`modules/frame-cloudrun-app`](../modules/frame-cloudrun-app/README.md).

**Out of scope (keep hand-rolled):**

- `identity-oauth2-hydra`
- `identity-authorization-keto`
- `edge-lb-*` (global HTTPS LB + DNS only)

## Why a composition module

Before streamlining, each app copied ~220–300 lines of identical OpenTofu
(SA, Neon, secrets, Pub/Sub push OIDC, migrate, Cloud Run, IAM). Domains
drifted on:

| Concern | Old drift | Canonical |
|---------|-----------|-----------|
| Keto URIs | identity often used `api.stawi.org`; ops/platform used CR | **Direct keto-read/write CR** |
| `use_http2` | ops true; others false | **true** |
| setup/migrate execute | identity true; ops/platform false | **false** (Job argv `["setup"]`) |
| OTEL exporters | ops none; others OTLP from edge | **none** on service |
| Keep-warm / probes | auth only | optional flags |
| Region default | west1 vs west9 | **europe-west1** |

## App root checklist

```
apps/<name>/
  app.yaml
  cloudrun/
    main.tf              # thin: providers + module.frame + app-only resources
    moved.tf             # one-time state moves (delete after green apply)
    variables.tf
    outputs.tf
    generated_secrets.tf # optional owned secrets
    backend.tf
    versions.tf
    envs/stawi-prod.tfvars
```

### `main.tf` shape

```hcl
provider "neon"  { api_key = var.neon_api_key }
provider "google" { project = var.project_id; region = var.region }

module "frame" {
  source     = "../../../modules/frame-cloudrun-app"
  app_name   = var.app_name
  project_id = var.project_id
  region     = var.region
  platform   = var.platform
  image      = var.image
  labels     = var.labels

  # ops/platform:
  identity_project_id = var.identity_project_id
  identity_region     = var.identity_region
  # identity domain: identity_project_id = null

  neon_org_id    = var.neon_org_id
  neon_region_id = var.neon_region_id
  resource_path  = "/my-path"
  app_env        = { /* only app-specific keys */ }
}
```

### Escape hatches

| Need | How |
|------|-----|
| Owned secrets | `generated_secrets.tf` + `extra_secret_*` / `secret_env_extra` |
| Multi-topic queues | `messaging_topics` + `messaging_subscriptions` (trustage) |
| Min instances | `min_instance_count = 1` (in-process schedulers) |
| Keep-warm | `enable_keep_warm = true`, probes on `/healthz` |
| No database | `has_database = false` |
| Extra jobs | sibling modules (e.g. tenancy `sync_job`) |

## Shared secret: `hydra-webhook-psk`

| Project | Owner of secret **value** | Consumers |
|---------|---------------------------|-----------|
| stawi-identity | `identity-oauth2-hydra` (excluded) | accessor IAM |
| stawi-operations | `operations-audit` (copies identity) | accessor IAM |
| stawi-platform | seeded out-of-band (same value) | accessor IAM |

Frame module grants runtime SA `secretAccessor` unless the secret is in
`extra_secret_ids` (owned by the app via `module.secrets`).

## Apply / state

First apply after migration uses `moved.tf` so resources are **relocated**, not
recreated. After a successful apply on all envs, delete `moved.tf`.

```bash
gh workflow run app-apply.yml -f app=platform-settings -f env=stawi-prod
# canary, then remaining Frame apps
```

## Messaging contract

```
publish  → gcppubsub://{project}/{app}-events
receive  → push://{app}-events?protocol=gcppubsub
GCP push → POST /_frame/queue/{app}-events  (OIDC as runtime SA)
```

Migrate jobs always use `EVENTS_QUEUE_URL=mem://frame.events.migrate`.

### Tenancy migrate + Keto (service-bot bootstrap)

Tenancy `migrate` does more than schema: after DB migrate it writes root/service-bot
relation tuples to Keto via Frame’s **gRPC** authorizer. That requires:

1. **Keto Cloud Run** with `use_http2 = true` (h2c) so gRPC works end-to-end.
2. **Frame client** using TLS for `https://…` AUTHORIZATION URIs and a Google ID
   token (Cloud Run invoker) — plaintext gRPC only for in-cluster `http://…`.
3. **Migrate job env** including the same OAuth/Keto URIs as the runtime service
   (`frame_oauth_env` merged into migrate), plus `OAUTH2_SIGNER_API_KEY` when using
   private_key_jwt.

`AUTHORIZATION_SERVICE_*` points at **`https://authz.stawi.org`** /
**`https://authz-w.stawi.org`** (stable DNS; Cloud Run `custom_audiences` +
invoker grants for `identity-tenancy@…` and other runtime SAs).
