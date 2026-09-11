# Manufacturing, fintech and chat deployment — design

Date: 2026-09-11. Status: approved by standing goal ("iterate until the
applications are fully functional"); chat placement revised mid-session.

## Goal

Get the three service families under `~/code` running in production:

| Family | Repo | Target |
|--------|------|--------|
| Fintech | antinvestor/service-fintech | Cloud Run, `stawi-finance` (existing account `finance`) |
| Manufacturing | antinvestor/service-manufacturing | Cloud Run, new project `stawi-manufacturing` (new account `manufacturing`) |
| Chat | stawilabs/chat | Kubernetes cluster (deployment.manifests, `communications` namespace) with Valkey as the gateway cache — **not** Cloud Run |

## Fintech

- Existing five services (funding, limits, loans, operations, savings) move
  from v1.96.22 to v1.96.27 via tfvars; rolled with `gcloud run` (same steps
  as `cloudrun-ship`).
- New stacks `apps/finance-stawi` (`/stawi`, Hydra client `service-stawi`)
  and `apps/finance-seed` (`/seed`, `service-seed`). Both are plain Frame
  apps on the shared `frame-cloudrun-app` module, Neon `finance` org,
  default events topic, setup job registers permissions (stawi also syncs
  `/workflows` into trustage).
- `stawi-finance` gets `cloudrun-ship` bootstrap; the service repo release
  workflow gains one ship job per finance service (7).
- Edge: `/stawi`, `/seed` routes added disabled; enabled after apply +
  `refresh-origins`.

## Manufacturing

- New GCP project `stawi-manufacturing` under the free-credit billing
  account; `bootstrap-gcp-account.sh`, `bootstrap-cloudrun-ship.sh`,
  `bootstrap-neon-account.sh --account manufacturing` (new Neon org
  "Stawi Manufacturing").
- Stack `apps/manufacturing` (`/manufacturing`, client
  `service-manufacturing`), image v0.2.0, Neon DB, default events topic.
- Release workflow gains a ship job; edge route `/manufacturing` added disabled.

## Chat (cluster)

- Manifests already exist: `namespaces/communications/chat-drone`
  (chat.stawi.org) and `chat-gateway` (gateway.stawi.org), Flux image
  automation ≥ v1.0.14. Change: gateway `CACHE_URI` → Valkey
  (`redis://valkey.datastore.svc:6379`) instead of NATS KV; NATS stays for
  queues.
- Precondition: the cluster's communications namespace, CNPG cluster, NATS,
  Valkey and gateway namespace must actually reconcile. Live state on
  2026-09-11 shows none of them running; see session notes.

## Verification

Per Cloud Run service: setup job succeeds, `/readyz` 200, permission
manifest present in Keto, edge route serves `/openapi.yaml`, one
authenticated smoke RPC via api.stawi.org. Chat: pods Ready, gateway stream
round trip through gateway.stawi.org.

## Out of scope

Dev environments; Supabase; K8s for fintech/manufacturing.
