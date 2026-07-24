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
owners: []          # optional team / CODEOWNERS-style list
envs:
  - stawi-dev       # add stawi-prod when ready
neon:
  # Domain org: identity | notifications | payments | platform | labs
  account: labs
runtime: cloudrun
```

| Field | Purpose |
|-------|---------|
| `name` | Human / inventory name (CI uses the **directory** name as `app_name`) |
| `envs` | Which platform envs this app deploys to; drives the plan/apply matrix |
| `neon.account` | Domain Neon **organization** key in `config/neon-accounts.yaml` (not a project name) |

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
| `platforms/stawi-dev` / `stawi-prod` | GCP project, region, labels (count-switch on `var.platform`) |
| `modules/edge-contract` | Public edge env (OAuth, CORS hosts, OTel) |
| `modules/neon-database` | One Neon project per app |
| `modules/pubsub` | **Always-on** messaging — default `{app}-events` topic + pull subscription |
| `modules/cloudrun-service` | Cloud Run service + runtime wiring |

### Messaging (automatic)

**Pub/Sub is automatic.** The template includes `module "messaging"` with defaults:

- Topic: `{app_name}-events`
- Pull subscription: `{app_name}-events-pull`
- Runtime env: `MESSAGING_BACKEND=pubsub`, plus `PUBSUB_TOPIC_*` / `PUBSUB_SUBSCRIPTION_*`

Do **not** wire cluster NATS/JetStream into apps in this repo. Override `topics` / `subscriptions` on the pubsub module only when you need extra topics.

Pub/Sub resources live in the **same GCP project** as Cloud Run (`local.platform.project_id`).

## 4. Neon credentials (multi-account)

1. Pick a **domain** account (`identity`, `notifications`, `payments`, `platform`, `labs`) — see [BACKEND.md](BACKEND.md) and the [multi-account design](superpowers/specs/2026-07-24-neon-multi-account-secrets-design.md).
2. Confirm the key exists in `config/neon-accounts.yaml` and respects `allowed_deploy_envs` / `allowed_app_prefixes` (e.g. payments apps should be named `payment-*` / `checkout-*` / …).
3. Ensure the GitHub **Environment** named `github_environment` (e.g. `neon-payments`) exists with secret **`NEON_API_KEY`** only.
4. CI loads that single key into `TF_VAR_neon_api_key` for that job — never commit API keys; never put all domain keys on the job.
5. Canonical operator copy of each key lives in Vault at `vault_path` (rotation source of truth).

## 5. Independent CI

| Event | Workflow | Behavior |
|-------|----------|----------|
| PR touching this app (or shared modules/platforms/config) | `app-plan.yml` | Plans **only** changed / module-impacted apps |
| Merge to `main` | `app-apply.yml` | Applies **only** that matrix |
| Manual | workflow_dispatch on plan/apply | Optional single `app` / `env` |

Change detection: [`.github/scripts/detect-changed-apps.sh`](../.github/scripts/detect-changed-apps.sh).

You do **not** need to edit monorepo-wide deploy lists. Path filters + detection keep CI independent per app.

## 6. Checklist before first PR

- [ ] Copied from `_template`, not hand-rolled K8s YAML
- [ ] `app.yaml` `neon.account` valid
- [ ] `envs/*.tfvars` image set; `platform` matches filename/env
- [ ] No `HelmRelease`, Flux, or other cluster manifests under `apps/`
- [ ] R2 + Neon (+ later GCP WIF) secrets present for CI
- [ ] Open PR → confirm plan matrix is only your app (and envs)
- [ ] Merge → apply; verify Cloud Run URI, Neon project, Pub/Sub topic

## What not to do

- Do **not** add Kubernetes YAML here (no HelmRelease, HTTPRoute, CNPG, NATS, Flux Kustomization).
- Do **not** point apps at cluster NATS; messaging is Cloud Pub/Sub only.
- Do **not** share one OpenTofu state across apps; each app/env has its own R2 key.
- Do **not** put platform project secrets in git; use GitHub secrets and WIF.
