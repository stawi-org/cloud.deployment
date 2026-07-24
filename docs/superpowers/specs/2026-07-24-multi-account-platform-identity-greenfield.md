# Multi-Account Platform + Identity Greenfield Architecture

**Date:** 2026-07-24  
**Status:** Accepted  
**Repo:** stawi-org/cloud.deployment

## Intent

Greenfield, big-bang capable platform where:

1. **Running an app = selecting accounts** — which **GCP account** and which **Neon account** supply resources.
2. **Nothing sensitive in git** — only registries (non-secret metadata).
3. **GCP Secret Manager** holds database URLs and all other runtime (and preferred deploy-time) secrets.
4. **Identity domain** is fully expressible as apps on Cloud Run + Neon + Pub/Sub (no cluster dependency for greenfield).

## Account model

```
app.yaml
  gcp.account  ──► config/gcp-accounts.yaml   ──► project_id, region, WIF, SM project
  neon.account ──► config/neon-accounts.yaml  ──► Neon org API key location (SM or GH Env)
  envs[]       ──► which env slices of those accounts to use
```

An application does **not** hardcode project IDs in Terraform for multi-tenancy of accounts. CI and local tooling **resolve** accounts → concrete IDs, then pass them as OpenTofu variables.

### GCP account registry (`config/gcp-accounts.yaml`)

Per logical account (e.g. `identity`, `payments`, `labs`), per deploy env (`stawi-dev`, `stawi-prod`):

| Field | Purpose |
|-------|---------|
| `project_id` | GCP project for Cloud Run, Pub/Sub, **Secret Manager**, runtime SA |
| `region` | Default Cloud Run / regional resources |
| `workload_identity_provider` | WIF provider resource name (not secret) |
| `deploy_service_account` | SA CI impersonates to apply tofu |
| `labels` | Standard resource labels |
| `github_environment` | Optional GH Environment for apply protection |

### Neon account registry (`config/neon-accounts.yaml`)

Unchanged domain keys (`identity`, `payments`, …), plus:

| Field | Purpose |
|-------|---------|
| `github_environment` | Fallback / protection for CI |
| `secret_manager` | Preferred: `{ gcp_account, secret_id }` where Neon **org API key** is stored for deploy |

Deploy-time Neon API key resolution order:

1. Secret Manager (if registry has `secret_manager`) via WIF after GCP auth  
2. Else GitHub Environment secret `NEON_API_KEY`

### Secret classes

| Class | Store | Consumers |
|-------|--------|-----------|
| DB connection strings | **Secret Manager** in app GCP project | Cloud Run `secret_key_ref` |
| App API keys, OAuth client secrets, Hydra system secret, webhook PSKs | **Secret Manager** | Cloud Run |
| Neon org API key (tofu provider) | **Secret Manager** (preferred) or GH Environment | CI only — never Cloud Run |
| R2 state credentials | GitHub repo secrets | CI only |
| Project IDs, WIF provider names, account keys | **Git registries** | CI + tofu vars |

**Never in git:** passwords, API keys, connection strings, Hydra system secrets, session secrets.

## App composition (repeatable root)

Every Frame/Cloud Run app root:

1. Resolve `project_id` / `region` from GCP account + env (vars from CI).  
2. Create runtime SA.  
3. `modules/neon-database` → Neon project.  
4. `modules/app-secrets` → write `DATABASE_URL` (+ optional extra secrets) to SM; IAM for runtime SA.  
5. `modules/pubsub` → topics/subscriptions + IAM.  
6. `modules/edge-contract` → non-secret edge env.  
7. `modules/cloudrun-service` → service with `secret_env` from SM.

Ory (Hydra/Keto) roots use the same account resolution + SM, with Ory-specific images/config modules.

## Identity greenfield set

| App directory | Role | neon.account | gcp.account |
|---------------|------|--------------|-------------|
| `identity-authentication` | Auth service + accounts UI | identity | identity |
| `identity-oauth2-hydra` | Ory Hydra | identity | identity |
| `identity-authorization-keto` | Ory Keto | identity | identity |
| `identity-tenancy` | Tenancy API | identity | identity |
| `identity-profile` | Profile API | identity | identity |
| `identity-identity` | Identity API | identity | identity |

All share **GCP account `identity`** and **Neon account `identity`**, different Neon **projects** per app.

Public hostnames (configure at go-live): `accounts.stawi.org`, `oauth2.stawi.org`, `api.stawi.*` path prefixes.

Big-bang: deploy all six, smoke OIDC, point DNS once. No CNPG/NATS migration.

## CI resolution

```
detect changed apps
  → for each (app, env):
       read app.yaml
       resolve gcp context (project, region, WIF, SA)
       resolve neon context (SM secret or GH env)
       auth WIF → GCP
       fetch neon API key from SM (or GH)
       tofu init/plan/apply with -var project_id=… region=…
```

One job = one app = one GCP project = one Neon org key.

## Local developer loop

```bash
./.github/scripts/resolve-app-context.sh <app> <env>
# exports / prints TF_VAR_* and hints for secrets
# Never commits resolved secrets
```

## Success criteria

- Adding an app is copy template + set `gcp.account` + `neon.account` + image.  
- Moving an app between GCP projects is a registry + app.yaml change, not a rewrite.  
- `git grep` finds no live credentials.  
- Runtime secrets only via Secret Manager references on Cloud Run.  
- Identity six-pack scaffolds exist and validate.  
