# Identity: cluster → Cloud Run parity

Source of truth: `deployment.manifests/namespaces/identity/*`.

Each app under `apps/identity-*/cloudrun` is **self-contained**: public URLs, OAuth env, migrate args, and secrets live in that app’s `main.tf` locals. There is **no** shared `identity-domain` module.

## Mapping

| Cluster | Cloud Run app |
|---------|----------------|
| `service-authentication` | `identity-authentication` |
| Hydra HelmRelease | `identity-oauth2-hydra` |
| Keto HelmRelease | `identity-authorization-keto` (`*-read` + `*-write`) |
| `service-identity` | `identity-identity` |
| `service-profile` | `identity-profile` |
| `service-tenancy` | `identity-tenancy` |

## Shared infrastructure modules only

Reusable plumbing (not domain aggregation):

- `modules/neon-database`, `app-secrets`, `pubsub`, `cloudrun-service`, `cloudrun-migrate-job`
- `modules/edge-contract` — minimal edge OTEL/OAuth defaults (apps override as needed)

## Intentional Cloud Run deltas

1. **Events (Frame)**: Frame v2 does **not** support `gcppubsub://`. Dual publish+subscribe (setupEventsQueue) only works with `mem://` or `nats://`. Cloud Run apps use app-scoped `mem://{app}-events` + `WithRegisterEvents` handlers — **not** the Frame default `frame.events.internal_._queue`. Pub/Sub topics `{app}-events` are always provisioned for durable/cross-service producers. Push to `POST /_frame/queue/{ref}` is Frame’s Cloud Run receive path (`push://{ref}`); that requires separate publish URLs (`ce+https` / `cloudtasks`) and is opt-in. Migrate jobs keep `mem://frame.events.migrate`.
2. **No Valkey**: set `CACHE_URI` when Memorystore exists.
3. **Hydra admin**: public serve only for now.
4. **Cross-service URIs**: each app hardcodes public hosts it depends on (`accounts` / `oauth2` / `api`).

## Deploy order

1. `identity-oauth2-hydra` (creates shared `hydra-webhook-psk`)
2. `identity-authorization-keto`
3. `identity-tenancy`
4. `identity-authentication`
5. `identity-profile` / `identity-identity`
