# Cloud Deployment Architecture

**Date:** 2026-07-24  
**Status:** Accepted  
**Repo:** `stawi-org/cloud.deployment` (this repository)

## Summary

`cloud.deployment` is the modular home for **Cloud Run + Neon + Cloud Pub/Sub** application deployments and reusable OpenTofu modules. It is the Cloud Run analogue of the Colony Helm chart pattern used on Kubernetes: shared modules hold the heavy lifting; each app is a thin composition root.

Kubernetes remains exclusively in `deployment.manifests`. Cluster foundation remains in `deployment.infra`. This repo does **not** hold HelmReleases, Flux Kustomizations, Gateway routes, CNPG, or NATS resources.

**Messaging for apps in this repo is always Google Cloud Pub/Sub** — not NATS/JetStream (those remain cluster-only under `deployment.manifests`). Edge/greenfield services publish and subscribe via Pub/Sub topics and subscriptions provisioned with the app stack.

First wave targets **greenfield / edge products** that talk to the existing platform only via **public edge** endpoints (`api.stawi.*`, `oauth2.stawi.org`, and related public hosts). No private mesh into the Talos cluster.

**Blast radius:** OpenTofu state and CI are **per app (and per environment)**. A change to one app runs only that app’s plan/apply. Shared module or platform changes fan out to **affected apps only**, still as independent jobs—not one mega-stack.

## Goals

1. Robust, extensible deployment architecture for hybrid runtimes (cluster stays; edge moves to Cloud Run + Neon).
2. Modular reuse comparable to Colony: change shared behaviour once, not in every app.
3. Independent app workflows: only changed (or impacted) apps plan/apply.
4. Clear repo boundaries so small platform changes do not require touching every application or the wrong repository.
5. Support Neon projects from **different Neon accounts/orgs**, with **one Neon project per app**.
6. Remote state on **Cloudflare R2** (aligned with `deployment.infra` state practices).
7. **Always use Cloud Pub/Sub** for async messaging in apps owned by this repo (no NATS for Cloud Run workloads).

## Non-Goals (first wave)

- Private connectivity from Cloud Run into the Talos cluster (VPC connector, internal LB, tunnel mesh).
- Migrating existing Colony/Flux services into this repository.
- In-cluster OpenTofu / Flux TF controller reconciling Cloud Run or Neon.
- Storing any Kubernetes deployment manifests here.
- A single monorepo OpenTofu root that plans all apps together.
- Using NATS/JetStream from Cloud Run apps (cluster NATS stays on K8s only).

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Repo role | New `cloud.deployment` owns Cloud Run + Neon modules and app stacks | Keeps K8s GitOps and serverless deploy models cleanly separated |
| K8s ownership | **Only** `deployment.manifests` | Operator clarity; Flux single app source of truth for the cluster |
| Cluster foundation | `deployment.infra` | Existing Talos/Flux/node ownership unchanged |
| Cloud provisioning | OpenTofu + **GitHub Actions** | No tofu-controller; audit via PR plan + main apply |
| Connectivity | Public edge only | Lowest ops cost for first wave; matches edge/product apps |
| First apps | Greenfield edge products | Avoid risk on identity/finance core path |
| Composition model | App-centric; runtime plugins via modules | Thin app roots; Colony-like reuse |
| Isolation | One OpenTofu root + state per app per env | Independent workflows and lock scope |
| Neon tenancy | **One Neon project per app** | Blast isolation; independent lifecycle and billing attribution |
| Neon accounts | **Multi-account / multi-org** | Projects may live under different Neon accounts |
| State backend | **Cloudflare R2** | Match infra; S3-compatible; not tied to a single GCP project |
| CI scope | Path + impact detection | Only changed/impacted apps run |
| Messaging (this repo) | **Google Cloud Pub/Sub always** | Serverless-native; no NATS dependency for edge apps; cluster keeps NATS |

## Repository boundaries

```
deployment.infra
  └── Nodes, Talos, Flux bootstrap, account WIF, DNS foundation, etc.

deployment.manifests
  └── ALL Kubernetes: providers, namespaces, Colony HelmReleases,
      Gateway, CNPG, NATS, Flux Kustomizations

cloud.deployment  (this repo)
  └── OpenTofu modules + per-app Cloud Run/Neon/Pub/Sub roots + app CI

antinvestor/charts (colony)
  └── Helm chart source consumed by deployment.manifests only
```

### What must never live here

- `HelmRelease`, `Kustomization` (Flux), `HTTPRoute`/`GRPCRoute`, CNPG `Cluster`/`Database`, NATS CRs, NetworkPolicy for cluster pods, Colony values trees.

### What may be shared by *contract* only

- Edge defaults (public API hosts, CORS allowlists, OTel endpoint policy, OAuth audience base URLs) live as the `edge-contract` module/data for Cloud Run apps.
- The same *policy* may be mirrored in Colony conventions / skills inside `deployment.manifests`—ownership of cluster YAML stays there. Optional later: CI drift checks between the two, without moving files.

## Target architecture

```
                    ┌─────────────────────────────────────┐
                    │     cloud.deployment (this repo)      │
                    │  modules + apps/* + GHA plan/apply    │
                    └───────────────┬─────────────────────┘
                                    │ OpenTofu apply (per app)
              ┌─────────────────────┼─────────────────────┐
              v                     v                     v
      ┌───────────────┐     ┌──────────────┐     ┌────────────────┐
      │  Cloud Run    │     │ Neon project │     │ Cloud Pub/Sub  │
      │  (per app)    │─────│  (per app)   │     │ topics/subs    │
      └───────┬───────┘ DB  └──────────────┘     │ (per app)      │
              │                ▲                 └───────▲────────┘
              │                │                         │
              └────────────────┴─────────────────────────┘
                    publish/subscribe + DATABASE_URL
              │ HTTPS public only (sync APIs)
              v
      ┌───────────────────────────────────────┐
      │  Public edge (Gateway / oauth2 / api)   │
      │  owned by deployment.manifests          │
      └───────────────────┬───────────────────┘
                          v
      ┌───────────────────────────────────────┐
      │  Talos cluster (Colony + NATS, etc.)    │
      │  — edge apps do not use cluster NATS    │
      └───────────────────────────────────────┘
```

## Repository layout

```
cloud.deployment/
  modules/                          # reusable; never applied as a root
    cloudrun-service/
    neon-database/
    pubsub/                         # topics + subscriptions (always for messaging)
    edge-contract/
  platforms/                        # env-level defaults (not apply roots)
    stawi-dev/
    stawi-prod/
  apps/
    _template/                      # copy-paste starter
      app.yaml
      cloudrun/
        main.tf
        backend.tf
        variables.tf
        versions.tf
        envs/
          stawi-dev.tfvars
          stawi-prod.tfvars
    <app-name>/                     # one independent root
      app.yaml
      cloudrun/
  .github/
    workflows/
      app-plan.yml                  # PR: plan changed/impacted apps only
      app-apply.yml                 # main: apply changed/impacted apps only
    scripts/
      detect-changed-apps.sh
      list-apps-using-module.sh
  docs/
    superpowers/specs/
    ADDING_AN_APP.md                # (implementation phase)
    MODULES.md
```

**Rule:** Only `apps/<name>/cloudrun` is an OpenTofu apply root. `modules/` and `platforms/` are never applied alone.

## Independent app workflows (blast radius)

### State layout (R2)

One state object **per app per environment**:

```
s3://<state-bucket>/cloud-deployment/apps/<app-name>/<env>/terraform.tfstate
```

Example:

```
cloud-deployment/apps/edge-portal/stawi-dev/terraform.tfstate
cloud-deployment/apps/edge-portal/stawi-prod/terraform.tfstate
```

- Backend: S3-compatible **Cloudflare R2** (same operational pattern as `deployment.infra` state).
- Credentials: GitHub Actions secrets / OIDC as adopted for R2 (never commit keys).
- Locking: use the backend’s locking support as configured for R2/S3-compatible state (document exact lock table/mechanism in implementation).

Because state is per app, applying `foo` never locks or mutates `bar`.

### What runs when

| Change path | CI behaviour |
|-------------|--------------|
| `apps/foo/**` only | Plan/apply **foo** only (envs inferred from changed tfvars or all configured envs for that app) |
| `apps/foo/**` + `apps/bar/**` | **foo** and **bar** in parallel independent jobs |
| `modules/<m>/**` | Detect consumer apps (those whose `*.tf` source that module) → plan/apply **only those apps** |
| `platforms/<env>/**` | All apps that use that platform/env → still **one job per app**, not one stack |
| Docs/scripts only | No app plan/apply |

### Concurrency

```yaml
concurrency:
  group: cloud-deploy-${{ matrix.app }}-${{ matrix.env }}
  cancel-in-progress: false
```

- Same app+env: serialize (no concurrent apply).
- Different apps: parallel.
- Never cancel an in-flight apply.

### Explicitly avoided

- Repo-root OpenTofu module that holds all apps.
- “Always plan every app on every PR.”
- Single shared state file for the monorepo.

## Module contracts

### `edge-contract`

**Purpose:** Data/defaults for public edge integration (Colony-like shared policy for serverless).

**Inputs:** environment name (optional overrides).

**Outputs / locals:** public API hostnames, CORS allow origin list, OTel export policy, OAuth audience base URLs, standard env key names. Messaging guidance is Pub/Sub-only (no NATS URLs).

**Non-responsibility:** Creating Gateway routes or DNS in the cluster.

### `pubsub`

**Purpose:** Provision Google Cloud Pub/Sub **topics and subscriptions** used by the app. **All async messaging for apps in this repo uses Pub/Sub** — not NATS.

**Inputs:** `project_id`, `app_name`, map of topics (optional per-topic config), map of subscriptions (topic key, ack deadline, push endpoint optional for push to Cloud Run), labels, optional dead-letter topic.

**Defaults:** At least one app-scoped topic pattern (e.g. `{app_name}-events`) so a copied template is usable without inventing topology; apps override/add topics in their thin root.

**IAM:** Grant the Cloud Run runtime service account `roles/pubsub.publisher` and/or `roles/pubsub.subscriber` as declared (publish-only vs consume).

**Outputs:** topic ids/names, subscription ids/names, env map (e.g. `PUBSUB_TOPIC_EVENTS`, `PUBSUB_SUBSCRIPTION_…`) for injection into Cloud Run.

**Non-responsibility:** Application message schemas; cross-project fan-out to cluster NATS (out of scope / bridge later if ever needed).

### `neon-database`

**Purpose:** Provision **one Neon project per app** (plus database/role/branch policy as needed).

**Multi-account requirement:**

- Each app selects a **Neon account/org context** (which API credentials / provider config to use).
- Modules must not hardcode a single Neon org.
- Pattern:

```hcl
# apps/<app>/cloudrun/envs/stawi-prod.tfvars
neon_account = "stawi-labs"   # maps to which credentials + provider alias
neon_region  = "aws-eu-central-1"
```

```hcl
# provider selection via aliases or separate provider blocks driven by var
provider "neon" {
  alias   = "account"
  api_key = var.neon_api_key  # injected from env/secret for the selected account
}
```

**Implementation guidance:**

- `app.yaml` (or tfvars) declares `neon.account` key.
- CI maps `neon.account` → GitHub secret / variable set (e.g. `NEON_API_KEY_STAWI_LABS`, `NEON_API_KEY_STAWI_ORG`).
- OpenTofu root passes the correct key into the module/provider; modules remain account-agnostic.

**Outputs:** project id, branch id, connection secret references (prefer writing URL to Secret Manager or equivalent; avoid long-lived plaintext in app config).

**Defaults:** pooled connection string for Cloud Run; scale-to-zero appropriate for edge apps unless overridden.

### `cloudrun-service`

**Purpose:** Cloud Run service, runtime service account, env wiring (including secret refs), scaling/concurrency, ingress, optional domain mapping.

**Inputs:** name, image, region, env map, secret env map, resource limits, `platform` locals from `platforms/*`.

**Outputs:** service URL, service account email.

**Non-responsibility:** Neon project creation (compose `neon-database` in the app root); cluster HTTPRoutes.

## Platform layer

`platforms/stawi-dev` and `platforms/stawi-prod` export env-level defaults:

- GCP project id / region for Cloud Run (may differ by env).
- Edge contract selection.
- Common labels (`app.kubernetes.io/*`-style or GCP labels).
- Backend config fragments for R2 (bucket name, endpoint, key prefix pattern)—apps still set their own state **key** to `apps/<app>/<env>/…`.

Platforms are **not** apply roots; apps `module "platform"` or `terraform.tfvars` + partial backend config.

## App model

### `app.yaml` (metadata for humans + CI)

```yaml
name: edge-portal
owners: [platform]
envs: [stawi-dev, stawi-prod]
neon:
  account: stawi-labs          # which Neon account/org credentials
runtime: cloudrun
# optional: modules impact hints if static analysis is insufficient
```

### Thin OpenTofu root

```hcl
module "platform" {
  source = "../../../platforms/stawi-prod"
}

module "edge" {
  source = "../../../modules/edge-contract"
  env    = "stawi-prod"
}

module "db" {
  source       = "../../../modules/neon-database"
  app_name     = var.app_name
  neon_region  = var.neon_region
  # provider configured at root for var.neon_account
}

module "messaging" {
  source     = "../../../modules/pubsub"
  project_id = module.platform.project_id
  app_name   = var.app_name
  # topics/subscriptions: app deltas; defaults provide {app}-events
}

module "service" {
  source = "../../../modules/cloudrun-service"
  name   = var.app_name
  image  = var.image
  env = merge(
    module.edge.service_env,
    module.messaging.service_env,
  )
  secret_env = module.db.secret_env
  # runtime SA also gets pubsub publisher/subscriber from module.messaging
}
```

Apps declare **deltas only** (image, scaling, extra env, Neon sizing, topic map). Shared hosts/CORS/OAuth bases come from modules/platforms. **Messaging is always Pub/Sub** via `modules/pubsub`.

## CI design

### Change detection algorithm

1. Compute git diff base…head.
2. Map paths:
   - `apps/<name>/**` → `{name}`
   - `modules/<m>/**` → all apps with `source` containing `modules/<m>` (rg/hcl parse)
   - `platforms/<env>/**` → apps listing that env in `app.yaml` / using that platform path
3. Emit JSON matrix: `{ app, env }[]`.
4. Empty matrix → success with “no deploy work”.

### PR: `app-plan.yml`

- Matrix over changed/impacted `(app, env)`.
- `tofu init` with R2 backend + app-specific key.
- Inject Neon credentials for `app.yaml` → `neon.account`.
- `tofu plan` + upload artifact; optional PR comment per app.

### Main: `app-apply.yml`

- Same matrix.
- `tofu apply` with concurrency group per app+env.
- `fail-fast: false` so one app failure does not cancel others.

### Module impact

Shared module changes **must** validate consumers but **must not** become a single apply. Fan-out remains N independent roots.

## Secrets and identity

| Secret class | Storage | Consumer |
|--------------|---------|----------|
| R2 state access | GitHub Actions secrets / OIDC | All app jobs |
| Neon API keys (per account) | GitHub Actions secrets, named by account key | Jobs for apps using that account |
| GCP deploy (Cloud Run) | WIF to deploy SA (pattern from `deployment.infra` GCP onboard) | App jobs |
| Runtime DB URL | Secret Manager (or agreed secret store) referenced by Cloud Run | Running service |

No long-lived cloud keys in git. No Neon admin keys in app images.

## Security and tenancy notes

- **Neon multi-account:** least privilege—CI only receives the Neon key for accounts needed by the matrixed apps in that run.
- **One project per app:** deletion or compromise of one edge app’s DB project does not share Neon project scope with others.
- **Public edge only:** treat all cluster API calls as internet-facing; use OAuth2/OIDC as existing platform requires; no reliance on cluster-internal DNS.
- **Pub/Sub only for messaging:** apps must not depend on cluster NATS; IAM is least-privilege publisher/subscriber on app topics.

## Adding a greenfield app (happy path)

1. Copy `apps/_template` → `apps/<name>`.
2. Set `app.yaml` (`neon.account`, envs, owners).
3. Fill image and any extra env/tfvars.
4. Open PR → CI plans **only** that app.
5. Merge → CI applies **only** that app.
6. Optional custom domain via module flag or DNS owned by `deployment.infra` / existing DNS process.

No edits to unrelated apps. No changes to `deployment.manifests` unless a later requirement needs a **cluster-side** route (out of scope for pure Cloud Run URL / Cloud Run domain mapping).

## Phased implementation (PR plan)

### PR 1 — Scaffold

- Repo layout, README, R2 backend convention, `platforms/stawi-dev` stub.
- `detect-changed-apps.sh` + dry-run workflows (matrix echo).
- `_template` app skeleton without real cloud resources.
- Docs: this spec + ADDING_AN_APP draft.

### PR 2 — Modules v1

- `edge-contract`, `neon-database` (multi-account provider pattern), `cloudrun-service`, **`pubsub`**.
- Unit/validation: `tofu validate` / `tflint` on modules.

### PR 3 — First pilot app (dev)

- Real edge app under `apps/<pilot>` targeting `stawi-dev`.
- Wire WIF + Neon account secret + R2 state.
- End-to-end plan/apply for that app only.

### PR 4 — Prod platform + guardrails

- `platforms/stawi-prod`.
- Branch protection / environment protection for apply.
- Concurrency and apply artifact retention.

### PR 5 — Module impact fan-out

- Consumer detection for `modules/**` and `platforms/**`.
- PR required plans for all consumers on module changes.

### PR 6 — Hardening

- MODULES.md, runbooks, secret rotation notes.
- Optional drift check docs vs Colony edge policy (no file moves).

## Alternatives considered

| Option | Why not chosen |
|--------|----------------|
| Flux also reads this repo for K8s apps | Rejected: all K8s must stay in `deployment.manifests` |
| Generate K8s into manifests from here | Extra pipeline; dual ownership risk |
| In-cluster tofu-controller | Rejected in favour of GHA OpenTofu for Cloud Run/Neon |
| One OpenTofu stack for all apps | Violates independent workflows; huge blast radius |
| One Neon project, many DBs | Weaker isolation; multi-account mapping harder |
| State in GCS only | Rejected: R2 for parity with infra and multi-cloud neutrality |
| NATS for Cloud Run messaging | Rejected: **Cloud Pub/Sub always** for apps in this repo; NATS stays cluster-only |

## Open questions (resolved)

| Question | Resolution |
|----------|------------|
| Neon project layout | **One Neon project per app** |
| Neon accounts | **Multiple accounts/orgs supported** via per-app `neon.account` → credential mapping |
| State backend | **Cloudflare R2**, key prefix `cloud-deployment/apps/<app>/<env>/` |
| K8s manifests location | **`deployment.manifests` only** |
| First wave connectivity | Public edge only |
| First wave apps | Greenfield edge products |
| Messaging | **Google Cloud Pub/Sub always** (not NATS) for apps owned here |

## Success criteria

- Changing one app’s image/tfvars runs CI for that app alone.
- Changing `modules/cloudrun-service` plans only apps that source it, each with its own state.
- Two apps can use two different Neon accounts without sharing API keys in config files.
- No Kubernetes YAML is added to this repository.
- A new edge app can be added by copying `_template` and filling deltas—no edits to other apps’ roots.
- Every app stack includes Pub/Sub messaging via `modules/pubsub` (no NATS client config for edge apps).
