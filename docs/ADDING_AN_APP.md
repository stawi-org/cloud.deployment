# Adding an app

This repo deploys **Cloud Run + Neon + Cloud Pub/Sub** stacks only.  
Kubernetes manifests (HelmRelease, Flux, HTTPRoute, CNPG, NATS, etc.) do **not** belong here — put those in [`deployment.manifests`](https://github.com/stawi-org/deployment.manifests).

## 1. Copy the template

```bash
cp -a apps/_template apps/<name>
```

Use a short DNS-/Cloud Run–safe name (lowercase, hyphens). Do not deploy `_template` itself; change detection ignores it.

## 2. Fill in `app.yaml`

```yaml
name: <name>
owners: []
envs:
  - stawi-prod          # prod-first; add stawi-dev when a real dev project exists
gcp:
  account: identity     # config/gcp-accounts.yaml → GCP project / WIF
neon:
  account: identity     # config/neon-accounts.yaml → Neon org
runtime: cloudrun
```

| Field | Purpose |
|-------|---------|
| `name` | Inventory name (CI uses **directory** name as `app_name`) |
| `envs` | Deploy envs; must exist under both GCP and Neon account registries. **Default: `stawi-prod` only** until dev is funded/bootstrapped |
| `gcp.account` | Which **GCP account** supplies project, region, Secret Manager, Pub/Sub, Cloud Run |
| `neon.account` | Which **Neon org** hosts this app’s database project |

```bash
./.github/scripts/resolve-app-context.sh <name> stawi-dev
```

## 3. Configure OpenTofu root (`apps/<name>/cloudrun`)

1. Edit `envs/stawi-dev.tfvars` (and `stawi-prod.tfvars` if listed):
   - `image` — container image for Cloud Run
   - `platform` — must match the env file (`stawi-dev` / `stawi-prod`)
2. Leave `app_name` as a placeholder if you like; CI always passes `-var=app_name=<directory>`.
3. Do **not** change the R2 backend pattern: state key is  
   `cloud-deployment/apps/<app>/<env>/terraform.tfstate`  
   (see [BACKEND.md](BACKEND.md)).

The template already composes:

| Module | Role |
|--------|------|
| `modules/edge-contract` | Public edge env (OAuth, CORS hosts, OTel) |
| `modules/neon-database` | One Neon project per app |
| `modules/app-secrets` | Secret Manager (pooled + **direct** DB URLs) |
| `modules/pubsub` | Messaging — default `{app}-events` topic + pull subscription |
| `modules/cloudrun-migrate-job` | **Migrations on apply** (`migrate` for Frame; override for Hydra/Keto) |
| `modules/cloudrun-service` | Cloud Run service (starts after migrate job succeeds) |

Migrations use the Neon **direct** connection string; the service uses the **pooled** URL.

### Messaging (automatic)

**Pub/Sub is automatic.** The template includes `module "messaging"` with defaults:

- Topic: `{app_name}-events` (+ matching subscription)
- Runtime env: `MESSAGING_BACKEND=pubsub`, app-scoped `EVENTS_QUEUE_URL=mem://{app}-events`, `EVENTS_QUEUE_NAME={app}-events`, plus `PUBSUB_TOPIC_*` / `PUBSUB_SUBSCRIPTION_*`
- Frame apps dispatch via `WithRegisterEvents` handlers (not the Frame default name `frame.events.internal_._queue`)
- Frame v2 has **no** `gcppubsub://` scheme; dual publish/subscribe uses `mem://` on Cloud Run. Durable push receive is `push://{ref}` → `POST /_frame/queue/{ref}` (separate publish via `ce+https` / Cloud Tasks)

Do **not** wire cluster NATS/JetStream into apps in this repo. Override `topics` / `subscriptions` on the pubsub module only when you need extra topics.

Pub/Sub resources live in the **same GCP project** as Cloud Run (`local.platform.project_id`).

## 4. Neon credentials (multi-account)

1. Pick a **domain** account (`identity`, `notifications`, `payments`, `platform`, `labs`) — see [BACKEND.md](BACKEND.md).
2. Confirm the key exists in `config/neon-accounts.yaml` and respects `allowed_deploy_envs` / `allowed_app_prefixes` (e.g. payments apps should be named `payment-*` / `checkout-*` / …).
3. Ensure SOPS file exists: `credentials/neon/<account>/auth.yaml` (from `bootstrap-neon-account.sh`).
4. CI decrypts that file with **`SOPS_AGE_KEY`** → `TF_VAR_neon_api_key` only when the app has `neon.account`.
5. Omit `neon:` entirely for GCP-only apps (no Neon key loaded).

## 5. Independent CI

| Event | Workflow | Behavior |
|-------|----------|----------|
| PR touching this app (or shared modules/platforms/config) | `app-plan.yml` | Plans **only** changed / module-impacted apps |
| Merge to `main` | `app-apply.yml` | Applies **only** that matrix |
| Manual | workflow_dispatch on plan/apply | Optional single `app` / `env` |

Repo secrets required: `R2_*` + `SOPS_AGE_KEY` — see [GITHUB_SECRETS.md](GITHUB_SECRETS.md).

Change detection: [`.github/scripts/detect-changed-apps.sh`](../.github/scripts/detect-changed-apps.sh).

You do **not** need to edit monorepo-wide deploy lists. Path filters + detection keep CI independent per app.

## 6. Checklist before first PR

- [ ] Copied from `_template`, not hand-rolled K8s YAML
- [ ] `app.yaml` `gcp.account` (+ optional `neon.account`) valid
- [ ] `envs/*.tfvars` image set; `platform` matches filename/env
- [ ] No `HelmRelease`, Flux, or other cluster manifests under `apps/`
- [ ] Repo secrets: R2 + `SOPS_AGE_KEY`; SOPS credential files for selected accounts
- [ ] Open PR → confirm plan matrix is only your app (and envs)
- [ ] Merge → apply; verify Cloud Run URI, Neon project, Pub/Sub topic

## What not to do

- Do **not** add Kubernetes YAML here (no HelmRelease, HTTPRoute, CNPG, NATS, Flux Kustomization).
- Do **not** point apps at cluster NATS; messaging is Cloud Pub/Sub only.
- Do **not** share one OpenTofu state across apps; each app/env has its own R2 key.
- Do **not** put platform project secrets in git; use GitHub secrets and WIF.
