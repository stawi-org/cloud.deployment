# Identity: cluster → Cloud Run parity

Source of truth: `deployment.manifests/namespaces/identity/*`.

## Mapping

| Cluster | Cloud Run app |
|---------|----------------|
| `service-authentication` | `identity-authentication` |
| `service-authentication-oauth2` (Hydra) | `identity-oauth2-hydra` |
| `service-authorization` (Keto) | `identity-authorization-keto` (**read + write** services) |
| `service-identity` | `identity-identity` (`service-fintech-identity` image) |
| `service-profile` | `identity-profile` |
| `service-tenancy` | `identity-tenancy` (`service-authentication-tenancy` image) |

## What is replicated

| Concern | Approach |
|---------|----------|
| Images/tags | Pinned to cluster Flux tags in `envs/stawi-prod.tfvars` |
| Neon DB per app | One Neon project each (was CNPG DBs) |
| Migrations | Cloud Run Job `{app}-migrate` before service |
| Hydra config | Env map from Helm values (`modules/identity-domain` → `hydra_env`) |
| Keto namespaces | Secret volume `namespaces.ts` from cluster ConfigMap |
| Keto read/write | Two Cloud Run services (`*-read` / `*-write`) |
| Frame OAuth2 (colony) | `OAUTH2_*` env including resource audience, requested audiences, private_key_jwt signer |
| CSRF / cookies / DEKs | SM secrets (random on first apply) |
| Google OAuth | `AUTH_PROVIDER_GOOGLE_*` (cluster names) via optional TF vars |
| Webhook PSK | Shared secret `hydra-webhook-psk` (owned by Hydra app) |
| Service mesh URLs | Public edge hosts (`accounts` / `oauth2` / `api`) via `identity-domain` |
| Events | Pub/Sub topics provisioned; **runtime `EVENTS_QUEUE_URL=mem://…`** until apps import `gcppubsub` |
| Cache | Cluster Valkey not yet wired (no Memorystore) — services run without `CACHE_URI` |
| Tenancy sync CronJob | Job definition `identity-tenancy-sync-partitions` (execute=false; schedule via Cloud Scheduler later) |
| Health | HTTP `/healthz` startup+liveness on authentication |

## Intentional Cloud Run differences

1. **NATS → mem/Pub/Sub**: Frame currently only registers NATS + mem drivers. Pub/Sub topics exist for the day services add `gocloud.dev/pubsub/gcppubsub`. Using `mem://` keeps migrate/runtime from hanging on NATS.
2. **No Valkey**: Set `CACHE_URI` when Memorystore is provisioned.
3. **Cross-namespace platform services** (`devices`, `files`, `notification`): pointed at `https://api.stawi.org/...` placeholders until those edges exist.
4. **Hydra admin**: single public serve process (cluster had public:4444 + admin:4445). Admin can be a second service later.
5. **DNS/gateway**: cluster HTTPRoutes remain the cutover; Cloud Run is ready for domain mapping.

## Deploy order

1. `identity-oauth2-hydra` (creates shared `hydra-webhook-psk`)
2. `identity-authorization-keto`
3. `identity-tenancy`
4. `identity-authentication`
5. `identity-profile` / `identity-identity`

## After first apply

1. Map custom domains: `accounts`, `oauth2`, `api` path backends.
2. Point `AUTHORIZATION_SERVICE_{READ,WRITE}_URI` at real Keto Cloud Run URLs (or domain).
3. Add Memorystore + `CACHE_URI` for authentication.
4. Enable `gcppubsub` in service images and switch `EVENTS_QUEUE_URL`.
