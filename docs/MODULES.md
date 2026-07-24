# Module reference

Shared OpenTofu modules and platform packs used by app roots under `apps/*/cloudrun`.

App roots are **thin**: they compose modules. **GCP project / region** come from CI via `resolve-app-context` (`gcp.account` + env). **Secrets** go to Secret Manager via `modules/app-secrets`.

---

## Architecture (compose order)

```
app.yaml gcp.account + env     → project_id, region, labels (CI vars)
modules/edge-contract          → public edge service_env
modules/neon-database          → Neon project + connection URIs
modules/app-secrets            → Secret Manager (DATABASE_URL, extra secrets) + accessor IAM
modules/pubsub                 → topics, subscriptions, publisher/subscriber IAM
modules/cloudrun-service       → Cloud Run (env + secret_env from SM)
```

Messaging is **always** Cloud Pub/Sub. Runtime secrets are **always** Secret Manager references (not plain values from git).

---

## `modules/edge-contract`

Public API / OAuth / OTel defaults for Cloud Run services talking to the Stawi edge.

### Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `env` | string | (required) | `stawi-dev` \| `stawi-prod` |

### Outputs

| Name | Description |
|------|-------------|
| `api_hosts` | List of public API host URLs |
| `cors_allow_origins` | CORS allow-origin list |
| `service_env` | Map of env vars for Cloud Run (`OAUTH2_*`, `OTEL_*`, `EDGE_ENV`, …) |
| `oauth_token_url` | OAuth token endpoint URL |

### Notes

- No cloud resources — pure locals/outputs.
- Override edge values in the app root if a single app needs different hosts.

---

## `modules/neon-database`

One **Neon project per app**. Account selection is **outside** the module: CI injects the API key from `app.yaml` → `config/neon-accounts.yaml` → GitHub secret → `TF_VAR_neon_api_key`.

### Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `app_name` | string | (required) | Neon project name prefix |
| `region_id` | string | `aws-eu-central-1` | Neon region |
| `pg_version` | number | `16` | Postgres major version |
| `database_name` | string | `app` | Database name |
| `role_name` | string | `app` | DB role name |
| `history_retention_seconds` | number | `86400` | Point-in-time retention |

### Outputs

| Name | Sensitive | Description |
|------|-----------|-------------|
| `project_id` | | Neon project id |
| `branch_id` | | Default branch id |
| `database_name` | | Database name |
| `role_name` | | Role name |
| `connection_uri` | yes | Direct connection URI |
| `pooled_connection_uri` | yes | Pooler URI (prefer for Cloud Run) |

### Multi-account Neon

| `neon.account` in app.yaml | GitHub secret (via registry) |
|----------------------------|------------------------------|
| `stawi-org` | `NEON_API_KEY_STAWI_ORG` |
| `stawi-labs` | `NEON_API_KEY_STAWI_LABS` |

Registry: [`config/neon-accounts.yaml`](../config/neon-accounts.yaml).

---

## `modules/cloudrun-service`

Cloud Run v2 service with optional external runtime SA and Secret Manager env bindings.

### Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | string | (required) | Service name |
| `project_id` | string | (required) | GCP project |
| `region` | string | (required) | GCP region |
| `image` | string | (required) | Container image |
| `service_account_email` | string | `null` | If set, use this SA (preferred: root-managed SA for secret IAM ordering) |
| `env` | map(string) | `{}` | Plain environment variables |
| `secret_env` | map(object) | `{}` | Env from Secret Manager (`secret`, optional `version`) |
| `cpu` | string | `1` | CPU limit |
| `memory` | string | `512Mi` | Memory limit |
| `max_instance_count` | number | `10` | Max instances |
| `min_instance_count` | number | `0` | Min instances |
| `concurrency` | number | `80` | Request concurrency |
| `ingress` | string | `INGRESS_TRAFFIC_ALL` | Ingress setting |
| `labels` | map(string) | `{}` | Resource labels |

### Outputs

| Name | Description |
|------|-------------|
| `uri` | Service URI |
| `service_account_email` | Runtime SA email |
| `name` | Service name |

---

## `modules/pubsub`

**Required messaging plane** for every app. Creates topics/subscriptions and grants the Cloud Run runtime SA publisher (and optionally subscriber) IAM.

Default when `topics` is empty and `create_default_events_topic = true`:

- Topic: `{app_name}-events`
- Pull subscription: `{app_name}-events` (same name as topic — required for Frame’s single `gcppubsub://project/name` URL for both OpenTopic and OpenSubscription)

### Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project_id` | string | (required) | GCP project (same as Cloud Run) |
| `app_name` | string | (required) | Used in default topic naming |
| `topics` | map(object) | `{}` | Logical topic key → config; empty → default events topic |
| `subscriptions` | map(object) | `{}` | Logical sub key → config; empty → default pull on events |
| `runtime_service_account_email` | string | (required) | Cloud Run runtime SA |
| `enable_publisher_iam` | bool | `true` | Grant `roles/pubsub.publisher` on topics |
| `create_default_events_topic` | bool | `true` | Create default events topic when `topics` empty |
| `labels` | map(string) | `{}` | Labels |

Topic object: optional `name`, `message_retention_duration` (default `604800s`).  
Subscription object: `topic_key`, optional `name`, `ack_deadline_seconds`, `message_retention_duration`, `push_endpoint`, `enable_subscriber_iam`.

### Outputs

| Name | Description |
|------|-------------|
| `topic_names` / `topic_ids` | Map logical key → name/id |
| `subscription_names` / `subscription_ids` | Map logical key → name/id |
| `service_env` | Env map for Cloud Run: `MESSAGING_BACKEND=pubsub`, `EVENTS_QUEUE_URL`, `EVENTS_QUEUE_NAME`, `PUBSUB_TOPIC_*`, `PUBSUB_SUBSCRIPTION_*` |
| `events_queue_url` / `events_queue_name` | Frame `EVENTS_QUEUE_*` values |

### Policy

- Do **not** add NATS modules or cluster messaging URLs for apps here.
- Pub/Sub uses the **same GCP project** as the Cloud Run service.

---

## Platforms (`platforms/stawi-dev`, `platforms/stawi-prod`)

Local-only packs (no resources). App roots select one with a count-switch:

```hcl
module "platform_dev" {
  source = "../../../platforms/stawi-dev"
  count  = var.platform == "stawi-dev" ? 1 : 0
}
module "platform_prod" {
  source = "../../../platforms/stawi-prod"
  count  = var.platform == "stawi-prod" ? 1 : 0
}
locals {
  platform = var.platform == "stawi-dev" ? module.platform_dev[0] : module.platform_prod[0]
}
```

CI passes `-var=platform=<env>` where env is `stawi-dev` or `stawi-prod`.

### Outputs (both)

| Name | Description |
|------|-------------|
| `env` | `stawi-dev` or `stawi-prod` |
| `project_id` | GCP project id (**placeholder** until real projects are set) |
| `region` | Default region (`europe-west1`) |
| `labels` | Common labels (`environment`, `managed-by`) |

Current placeholders: `stawi-cloudrun-dev` / `stawi-cloudrun-prod` — replace before pilot apply.

---

## R2 state key pattern

```
cloud-deployment/apps/<app>/<env>/terraform.tfstate
```

Bucket: `cloud-tofu-state` (prefix-isolated from other repos).  
Fragment: [`config/r2-backend.hcl`](../config/r2-backend.hcl). Details: [BACKEND.md](BACKEND.md).

---

## App template (`apps/_template`)

Canonical composition root. Copy to `apps/<name>` — see [ADDING_AN_APP.md](ADDING_AN_APP.md).

Root-owned extras (not modules):

- `google_secret_manager_secret` for `DATABASE_URL`
- Runtime `google_service_account` + secret accessor IAM
- `module.messaging` → merges `service_env` into Cloud Run
