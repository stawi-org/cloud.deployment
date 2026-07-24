# Modules

Shared OpenTofu modules under `modules/`. App roots compose these; they do not create cross-app resources.

| Module | Purpose |
|--------|---------|
| `modules/edge-contract` | Public edge env (OAuth hosts, CORS, OTel defaults) |
| `modules/neon-database` | One Neon project + role + DB per app |
| `modules/app-secrets` | Secret Manager secrets + accessor IAM |
| `modules/pubsub` | Topics, subscriptions, IAM, Frame dual-URL env |
| `modules/cloudrun-migrate-job` | One-shot migrate job executed on apply |
| `modules/cloudrun-service` | Cloud Run v2 service |

---

## `modules/edge-contract`

Local-only. Outputs `service_env` map for OAuth/CORS/OTel host defaults by `env` (`stawi-dev` / `stawi-prod`).

---

## `modules/neon-database`

Creates a Neon project for the app. Outputs pooled + direct connection URIs.

---

## `modules/app-secrets`

Creates Secret Manager secrets and grants `roles/secretmanager.secretAccessor` to runtime SA(s).

---

## `modules/cloudrun-service`

Cloud Run v2 service wrapper: image, scaling, secret/env, optional secret/GCS volumes, probes.

### Outputs

| Name | Description |
|------|-------------|
| `uri` | Service URI |
| `service_account_email` | Runtime SA email |
| `name` | Service name |

---

## `modules/pubsub`

**Required messaging plane** for every app. Creates topics/subscriptions and grants the Cloud Run runtime SA publisher (and optionally subscriber) IAM.

### Frame pattern (v2.0.10+)

```
publish  → gcppubsub://{project}/{app}-events     (OpenTopic)
receive  → push://{app}-events?protocol=gcppubsub (HTTP demux)
GCP push → POST https://{service}/_frame/queue/{app}-events
```

`service_env` emits dual URLs **and the full push OIDC suite** whenever `default_push_endpoint` + `push_oidc_service_account_email` are set:

| Env | Value |
|-----|--------|
| `EVENTS_QUEUE_PUBLISH_URL` | `gcppubsub://{project}/{app}-events` |
| `EVENTS_QUEUE_SUBSCRIBE_URL` | `push://{app}-events?protocol=gcppubsub` |
| `EVENTS_QUEUE_URL` | same as publish (legacy single-URL fallback) |
| `EVENTS_QUEUE_NAME` | `{app}-events` (Frame demux ref) |
| `FRAME_QUEUE_PUSH_AUTH` | `oidc` |
| `FRAME_QUEUE_PUSH_REQUIRE_AUTH` | `true` |
| `FRAME_QUEUE_PUSH_OIDC_AUDIENCE` | push endpoint URL (must match Pub/Sub OIDC audience) |
| `FRAME_QUEUE_PUSH_OIDC_ISSUERS` | `https://accounts.google.com,accounts.google.com` |
| `FRAME_QUEUE_PUSH_OIDC_JWKS_URL` | `https://www.googleapis.com/oauth2/v3/certs` |
| `FRAME_QUEUE_PUSH_OIDC_ALLOWED_EMAILS` | runtime SA email used for push |

Push without OIDC is rejected (`check.frame_push_requires_oidc`).

Migrate jobs keep `EVENTS_QUEUE_URL=mem://frame.events.migrate` (no Pub/Sub needed for schema).

### Defaults

When `topics` is empty and `create_default_events_topic = true`:

- Topic: `{app_name}-events`
- Subscription:
  - **Push** (when `default_push_endpoint` set): `{app_name}-events-push` → Frame path
  - **Pull** (otherwise): `{app_name}-events`
- Optional DLQ topic: `{app_name}-events-dlq` (push path only when `create_dead_letter_topic`)

### Regional storage

Prefer the workload region only so messages do not traverse continents:

```hcl
region                        = var.region
allowed_persistence_regions   = [var.region]
enforce_in_transit            = true
```

### Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project_id` | string | (required) | GCP project (same as Cloud Run) |
| `app_name` | string | (required) | Used in default topic naming |
| `region` | string | `""` | Workload region; used as sole persistence region when list empty |
| `topics` | map(object) | `{}` | Logical topic key → config; empty → default events topic |
| `subscriptions` | map(object) | `{}` | Logical sub key → config; empty → default sub |
| `runtime_service_account_email` | string | (required) | Cloud Run runtime SA |
| `enable_publisher_iam` | bool | `true` | Grant `roles/pubsub.publisher` on topics |
| `create_default_events_topic` | bool | `true` | Create default events topic when `topics` empty |
| `allowed_persistence_regions` | list(string) | `[]` | Regions where Pub/Sub may store messages |
| `enforce_in_transit` | bool | `true` | Keep in-transit messages in allowed regions |
| `default_push_endpoint` | string | `null` | Frame push URL `https://…/_frame/queue/{ref}` |
| `push_oidc_service_account_email` | string | `""` | SA Pub/Sub uses for OIDC + Frame allowlist (**required** when push endpoint set) |
| `push_oidc_audience` | string | `""` | `FRAME_QUEUE_PUSH_OIDC_AUDIENCE` (defaults to push endpoint) |
| `push_oidc_issuers` | string | `""` | `FRAME_QUEUE_PUSH_OIDC_ISSUERS` (defaults to Google accounts) |
| `push_oidc_jwks_url` | string | `""` | `FRAME_QUEUE_PUSH_OIDC_JWKS_URL` (defaults to Google JWKS) |
| `create_dead_letter_topic` | bool | `true` | Create DLQ + attach dead-letter policy |
| `dead_letter_max_delivery_attempts` | number | `10` | Max delivery attempts before DLQ |
| `pubsub_service_agent_email` | string | `""` | `service-{num}@gcp-sa-pubsub.iam.gserviceaccount.com` |
| `labels` | map(string) | `{}` | Labels |

Topic object: optional `name`, `message_retention_duration` (default `604800s`).  
Subscription object: `topic_key`, optional `name`, `ack_deadline_seconds`, `message_retention_duration`, `push_endpoint`, `enable_subscriber_iam`.

### Outputs

| Name | Description |
|------|-------------|
| `topic_names` / `topic_ids` | Map logical key → name/id |
| `subscription_names` / `subscription_ids` | Map logical key → name/id |
| `events_topic_name` / `events_subscription_name` / `events_ref` | Default events identifiers |
| `frame_publish_url` / `frame_subscribe_url` | Dual Frame URLs |
| `frame_push_handler_path` | `/_frame/queue/{ref}` |
| `service_env` | Full env map for Cloud Run Frame services |

### Policy

- Do **not** add NATS modules or cluster messaging URLs for apps here.
- Pub/Sub uses the **same GCP project** as the Cloud Run service.
- Frame apps need Frame ≥ **v2.0.10** (dual URL + GCP push codec); prefer **v2.0.11+** for OIDC SA allowlist.
- Blank-import `_ "gocloud.dev/pubsub/gcppubsub"` in service `main` (Frame also imports it from v2.0.9+).

### App wiring checklist (Frame)

```hcl
locals {
  service_run_url      = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  events_ref           = "${var.app_name}-events"
  events_push_endpoint = "${local.service_run_url}/_frame/queue/${local.events_ref}"
}

module "messaging" {
  source                          = "../../../modules/pubsub"
  project_id                      = var.project_id
  app_name                        = var.app_name
  region                          = var.region
  runtime_service_account_email   = google_service_account.runtime.email
  allowed_persistence_regions     = [var.region]
  enforce_in_transit              = true
  default_push_endpoint           = local.events_push_endpoint
  # Always pair push with OIDC — service_env emits full FRAME_QUEUE_PUSH_OIDC_*.
  push_oidc_service_account_email = google_service_account.runtime.email
  push_oidc_audience              = local.events_push_endpoint
  pubsub_service_agent_email      = "service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  create_dead_letter_topic        = true
}

# Pub/Sub agent can mint OIDC tokens as the runtime SA
resource "google_service_account_iam_member" "pubsub_push_token_creator" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Runtime SA can invoke Cloud Run (push delivery)
resource "google_cloud_run_v2_service_iam_member" "pubsub_push_invoker" {
  project  = var.project_id
  location = var.region
  name     = module.service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.runtime.email}"
}
```

---

## Platforms (`platforms/stawi-dev`, `platforms/stawi-prod`)

Local-only packs (no resources). App roots select one with a count-switch:

```hcl
module "platform_dev" {
  source = "../../../platforms/stawi-dev"
  count  = var.platform == "stawi-dev" ? 1 : 0
}
```
