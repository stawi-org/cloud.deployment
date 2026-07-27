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

1. Edit `envs/stawi-prod.tfvars` (and `stawi-dev.tfvars` if listed):
   - `image` — container image for Cloud Run
   - `platform` — must match the env file (`stawi-dev` / `stawi-prod`)
   - `resource_path` — OAuth path under `api.stawi.org` (e.g. `/devices`)
2. Leave `app_name` as a placeholder if you like; CI always passes `-var=app_name=<directory>`.
3. Do **not** change the R2 backend pattern: state key is  
   `cloud-deployment/apps/<app>/<env>/terraform.tfstate`  
   (see [BACKEND.md](BACKEND.md)).

### Shared stack: `modules/frame-cloudrun-app`

Frame apps call **one** composition module (see [FRAME_CLOUDRUN_APP.md](FRAME_CLOUDRUN_APP.md)):

| Piece | Role |
|-------|------|
| Hydra + Keto data | OIDC + ReBAC URIs (same- or cross-project) |
| `edge-contract` | Public edge defaults |
| Neon + SM | Pooled runtime URL + direct setup-job URL |
| Pub/Sub | Regional `{app}-events` + Frame push OIDC |
| Migrate job | `execute=false` by default; `mem://` events |
| Cloud Run | h2c, public invoker, OAuth/Keto env |
| Push IAM | Pub/Sub token creator + run.invoker |

**Not for Hydra/Keto/edge-lb** — those stay special-cased.

App `main.tf` should only set:

- `module.frame` inputs (identity project, resource path, memory, …)
- `app_env` / `secret_env_extra` for **app-only** knobs
- Optional `generated_secrets.tf` when this app owns SM values

Migrations use the Neon **direct** connection string; the service uses the **pooled** URL.

### Messaging (automatic)

**Pub/Sub is automatic** inside `frame-cloudrun-app`:

- Topic: `{app_name}-events` with **regional** `message_storage_policy`
- Push subscription → `POST https://{service}/_frame/queue/{app}-events`
- Runtime env (Frame ≥2.0.10): dual-URL `EVENTS_QUEUE_*` + full `FRAME_QUEUE_PUSH_OIDC_*`
- Setup jobs use argv `["setup"]` + `DO_SETUP=true` (full plan); keep `EVENTS_QUEUE_URL=mem://frame.events.migrate`
- Services must blank-import `_ "gocloud.dev/pubsub/gcppubsub"` and depend on Frame ≥ **v2.0.10**

Do **not** wire cluster NATS/JetStream here. Multi-topic apps (e.g. trustage) pass
`messaging_topics` / `messaging_subscriptions` into `module.frame`.

Pub/Sub resources live in the **same GCP project** as Cloud Run.

## 4. Neon credentials (multi-account)

1. Pick a **domain** account (`identity`, `notifications`, `payments`, `platform`, `labs`) — see [BACKEND.md](BACKEND.md).
   - **Platform apps** (`platform-*`) must use `neon.account: platform` (org `org-calm-cell-68997035`) and `gcp.account: platform`.
   - **Identity apps** (`identity-*`) must use `neon.account: identity` — never share the identity Neon org with platform.
2. Confirm the key exists in `config/neon-accounts.yaml` and respects `allowed_deploy_envs` / `allowed_app_prefixes` (e.g. `platform-*`, `identity-*`, payments `payment-*` / `checkout-*` / …).
3. Ensure SOPS file exists: `credentials/neon/<account>/auth.yaml` (from `bootstrap-neon-account.sh`).
4. CI decrypts that file with **`SOPS_AGE_KEY`** → `TF_VAR_neon_api_key` only when the app has `neon.account`.
5. Omit `neon:` entirely for GCP-only apps (no Neon key loaded).

## 5. Independent CI

| Event | Workflow | Behavior |
|-------|----------|----------|
| PR touching this app (or shared modules/platforms/config) | `app-plan.yml` | Plans **only** changed / module-impacted apps |
| Merge to `main` | `app-apply.yml` | Applies **only** that matrix |
| Manual | workflow_dispatch on plan/apply | Optional single `app` / `env` |

### Image updates (Frame services)

**Do not** rely on OpenTofu for routine image bumps. Service repos ship directly to Cloud Run via WIF + [`cloudrun-ship`](https://github.com/antinvestor/common/blob/main/.github/workflows/cloudrun-ship.yml) on each `v*.*.*` tag. See [CLOUDRUN_SHIP.md](CLOUDRUN_SHIP.md).

OpenTofu ignores container image on services/setup jobs so infra applies never clobber a ship.

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
