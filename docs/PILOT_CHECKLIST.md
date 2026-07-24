# Pilot checklist

Manual go-live checks for the **first edge app** on this scaffold.  
Not a production migration of existing cluster workloads.

## Prerequisites

1. [ ] Create GitHub **repo** secrets:
   - `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`
2. [ ] Create GitHub **Environments** (each with secret `NEON_API_KEY` only):
   - `neon-labs` (pilot often uses `neon.account: labs`)
   - plus `neon-identity`, `neon-notifications`, `neon-payments`, `neon-platform` as needed
   - Source keys from Vault paths in `config/neon-accounts.yaml` (see multi-account design)
2. [ ] Set `platforms/stawi-dev` (and prod if used) `project_id` to real GCP projects  
   (placeholders: `stawi-cloudrun-dev` / `stawi-cloudrun-prod`)
3. [ ] Configure Workload Identity Federation for Actions → deploy SA  
   - Secrets: `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`
   - Enable the WIF step in `.github/workflows/app-tofu.yml` (`if: false` → true)
4. [ ] Confirm the deploy SA can manage Cloud Run, Secret Manager, and **Pub/Sub** in that project

## App bootstrap

5. [ ] Copy `apps/_template` → `apps/hello-edge` (or real pilot name)  
   Follow [ADDING_AN_APP.md](ADDING_AN_APP.md)
6. [ ] Set `app.yaml` (`name`, `envs`, `neon.account`) and `envs/*.tfvars` `image`
7. [ ] Open a PR that only adds that app → confirm plan matrix is **one cell** (or one per env)
8. [ ] Plan succeeds against R2 key  
    `cloud-deployment/apps/<app>/stawi-dev/terraform.tfstate`

## Apply and verify

9. [ ] Merge → apply completes without error
10. [ ] `curl` (or browser) the Cloud Run service URI from outputs
11. [ ] Confirm Neon project created under the expected Neon account/org
12. [ ] Confirm `DATABASE_URL` secret exists and the runtime SA can access it

### Pub/Sub verification

13. [ ] Topic exists in the **same GCP project** as Cloud Run, e.g. `{app}-events`
14. [ ] Pull subscription exists, e.g. `{app}-events` (same name as topic for Frame)
15. [ ] Cloud Run revision env includes:
    - `MESSAGING_BACKEND=pubsub`
    - `EVENTS_QUEUE_URL=gcppubsub://{project}/{app}-events`
    - `EVENTS_QUEUE_NAME={app}-events`
    - `PUBSUB_TOPIC_EVENTS` / `PUBSUB_SUBSCRIPTION_EVENTS` as applicable
16. [ ] Runtime SA has `roles/pubsub.publisher` on the topic (and subscriber on the sub)
17. [ ] Frame blank-imports `gocloud.dev/pubsub/gcppubsub`; handlers receive via `WithRegisterEvents`
18. [ ] App can publish a test message (or admin tooling shows topic traffic)

## Boundaries

18. [ ] Confirm **no** files under `deployment.manifests` were required for this pilot
19. [ ] Confirm no HelmRelease / Flux / NATS wiring was added under `apps/` or `modules/`
20. [ ] Messaging is **not** pointed at cluster NATS

## Optional follow-ups

- [ ] Add `stawi-prod` env + tfvars when ready for a second environment
- [ ] Custom Pub/Sub topics/subscriptions beyond the default events topic
- [ ] Tighten Cloud Run ingress / auth as product requires
- [ ] Document secret rotation for Neon + R2
