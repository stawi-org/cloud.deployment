# Cluster → Cloud Run environment parity

Audit of Colony HelmRelease env (deployment.manifests) against
`modules/frame-cloudrun-app` + per-app `app_env` / secrets.

## Translation rules

| Cluster | Cloud Run |
|---------|-----------|
| `http://service-*.*.svc` | Edge DNS (`https://{host}.stawi.org`) or Keto/Hydra `*.run.app` for gRPC/IAM |
| `nats://…` `EVENTS_QUEUE_URL` | `gcppubsub://` + dual-URL Frame push (module/pubsub) |
| `NATS_CREDENTIALS_FILE` / SPIFFE / `K8S_*` | Omitted (not applicable) |
| `DATABASE_USERNAME` / `PASSWORD` | Single `DATABASE_URL` Secret Manager |
| `PERMISSIONS_REGISTRATION_URL` | Prefer bulk **setup plan** (`setup.Registry` / Job argv `setup migrate permissions …`). Abstract API: Frame package `setup` (`Step`, `Registry.Run`). Runtime PreStart optional via `PERMISSIONS_REGISTER_ON_START` (default true for Colony). Prod URL: `https://tenancy.stawi.org/_internal/register/permissions` |
| `redis://valkey.datastore.svc` | `mem://` or omit until Memorystore |
| OAuth2 / audiences / private_key_jwt | Injected by `frame_oauth_env` (Colony chart parity) |

## Per-app status (stawi-prod)

### Identity

| App | Cluster-specific envs transferred |
|-----|-----------------------------------|
| **identity-authentication** | Service URIs (profile/tenancy/devices/files), FedCM/Hydra public DNS, Google callback+scopes, default tenant/partition, CSRF/cookies, CACHE_URI=mem, EXPOSE_ERRORS |
| **identity-tenancy** | `SYNCHRONISE_PRIMARY_PARTITIONS`, `PROFILE_SERVICE_URI`, `DATABASE_LOG_QUERIES`; **no** self `PERMISSIONS_REGISTRATION_URL` |
| **identity-identity** | Profile/tenancy DNS URIs, notification api path, workload paths, max agent depth |
| **identity-profile** | DEK secrets, notification URI, TRACE_REQUESTS |
| **identity-oauth2-hydra** | Dedicated Hydra stack (not frame module) — CORS, hooks, DSN |
| **identity-authorization-keto** | Dedicated Keto stack — DSN, namespaces |

### Platform

| App | Notes |
|-----|--------|
| **platform-devices** | TURN_PROVIDER/TTL/URLs, analysis queue → Pub/Sub; Cloudflare TURN secrets optional via TF_VAR |
| **platform-files** | STORAGE_PROVIDER, S3/GCS/local bucket names; S3 credentials optional TF_VAR |
| **platform-geolocation / settings** | Frame defaults + permissions registration |

### Operations

| App | Notes |
|-----|--------|
| **operations-audit** | `AUDIT_SIGNING_KEY`, `DATABASE_LOG_QUERIES` |
| **operations-formstore** | MAX_SUBMISSION_SIZE, SUBMISSION_RATE_LIMIT, FILE_SERVICE_URL → files.stawi.org |
| **operations-queuestore** | ENQUEUE_RATE_LIMIT, STATS_CACHE_TTL_SECONDS |
| **operations-redirect** | JOBS_BASE_URL, LINK_EXPIRED_WEBHOOKS (empty until opportunities migrates), analytics optional |
| **operations-thesa** | ANALYTICS_BACKEND_TYPE; backend URL/token optional secrets |
| **operations-trustage** | Full queue dual-URL map + batch/retention knobs from colony |

## Operator secrets still required (not in git)

Seed with `scripts/seed-gcp-secrets.sh` or CI `TF_VAR_*`:

| Secret / var | Apps |
|--------------|------|
| `TF_VAR_google_oauth_client_id` / `_secret` | identity-authentication (Google login) |
| `TF_VAR_s3_endpoint` / `s3_access_key_*` | platform-files |
| `TF_VAR_cloudflare_turn_*` | platform-devices |
| `TF_VAR_analytics_*` | redirect, thesa |
| `hydra-webhook-psk` | all Frame apps (signer) |

## Intentionally not copied

- Cluster NATS JetStream URL shapes (replaced by Pub/Sub)
- SPIFFE workload API sockets
- Valkey internal DNS (no Memorystore yet)
- Product-opportunities in-cluster webhooks (empty until those apps migrate)
- Placeholder TURN secrets (`setmecorrectly`) until real TURN is configured
