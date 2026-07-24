# Remote state and credentials

## R2 state backend

OpenTofu remote state is stored in **Cloudflare R2** (S3-compatible), matching `deployment.infra`.

### Shared fragment

Apps use the partial backend config at [`config/r2-backend.hcl`](../config/r2-backend.hcl). The state **key** is supplied at `tofu init` (not in the fragment).

### State key pattern

```
cloud-deployment/apps/<app>/<env>/terraform.tfstate
```

### Init example

```bash
export R2_ACCOUNT_ID=...
export AWS_ACCESS_KEY_ID=...      # R2 access key
export AWS_SECRET_ACCESS_KEY=...  # R2 secret key

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
KEY="cloud-deployment/apps/<app>/<env>/terraform.tfstate"

tofu init \
  -backend-config=../../../config/r2-backend.hcl \
  -backend-config="key=${KEY}" \
  -backend-config="endpoints={s3=\"${ENDPOINT}\"}"
```

### Bucket sharing with deployment.infra

The same R2 bucket name as `deployment.infra` (`cluster-tofu-state`) is **intentional**. Isolation is by **key prefix** `cloud-deployment/apps/<app>/<env>/`.

Native S3 lockfiles (`use_lockfile = true` in the backend fragment) provide state locking — no DynamoDB table.

---

## Neon multi-account secrets (thorough model)

**Full design:** [docs/superpowers/specs/2026-07-24-neon-multi-account-secrets-design.md](superpowers/specs/2026-07-24-neon-multi-account-secrets-design.md)

### Why multiple accounts

| Account key | Domain | Isolation purpose |
|-------------|--------|-------------------|
| `identity` | Auth / profile / tenancy edges | Critical identity data blast radius |
| `notifications` | Notification workers | Volume + content isolation |
| `payments` | Checkout / billing edges | Compliance-sensitive |
| `platform` | Shared non-sensitive edges | Default platform |
| `labs` | Experiments | No prod data; dev-only envs |

Each key maps to a **separate Neon Organization** (not only projects under one org), so API keys and console membership do not span domains.

### Layer A — Registry (git, no secrets)

[`config/neon-accounts.yaml`](../config/neon-accounts.yaml) holds:

- `github_environment` — GitHub Actions Environment name
- `vault_path` — canonical operator store path
- `allowed_deploy_envs` — e.g. labs cannot use `stawi-prod`
- `allowed_app_prefixes` — e.g. payments only `payment-*`, `checkout-*`, …
- `owners`, `sensitivity`, deprecation flags

Apps select an account:

```yaml
# apps/checkout-edge/app.yaml
neon:
  account: payments
```

### Layer B — Secret material (never git)

#### Primary for CI: GitHub Environments

| GitHub Environment | Secret name | Content |
|--------------------|-------------|---------|
| `neon-identity` | `NEON_API_KEY` | Identity Neon org API key |
| `neon-notifications` | `NEON_API_KEY` | Notifications org API key |
| `neon-payments` | `NEON_API_KEY` | Payments org API key |
| `neon-platform` | `NEON_API_KEY` | Platform org API key |
| `neon-labs` | `NEON_API_KEY` | Labs org API key |

**Create each Environment** in the repo settings, add secret `NEON_API_KEY`, and enable protection rules for payments/identity (required reviewers on apply).

CI jobs set `environment: neon-<account>` so the job receives **only that one key**. We deliberately do **not** use repo-level `NEON_API_KEY_IDENTITY` + dump-all-keys-into-env (GitHub cannot dynamically index secrets, which forces co-location).

#### Canonical / human: Vault (OpenBao)

```
secret/data/cloud-deployment/neon/<account_key>
  api_key: "..."
```

- Rotate in Vault first, then update the matching GitHub Environment secret.
- Team policies: finance can write `.../neon/payments` only.
- Phase 2: GHA OIDC → Vault read of a single path (even stronger audit).

#### Rejected for Neon org API keys

- Committing keys (plain or SOPS in this repo) as the primary path
- Shipping org API keys into Cloud Run runtime env
- One shared super-key for all domains

### Layer C — Injection

1. Detect app → read `neon.account` → resolve `github_environment` from registry  
2. Job `environment: <github_environment>`  
3. `TF_VAR_neon_api_key=${{ secrets.NEON_API_KEY }}` (masked)  
4. OpenTofu `provider "neon" { api_key = var.neon_api_key }`  

Policy is enforced by `.github/scripts/validate-neon-accounts.sh` in the validate workflow.

### Ops: bootstrap checklist

1. Create Neon orgs (Identity, Notifications, Payments, Platform, Labs).  
2. Create API keys labeled `cloud-deployment-gha`.  
3. Write each key to Vault path `cloud-deployment/neon/<account>`.  
4. Create GitHub Environments `neon-*` with secret `NEON_API_KEY`.  
5. Restrict who can edit Environment secrets; require reviewers for `neon-payments`.  
6. Run validate workflow green.

### Rotation

1. Mint new Neon key → update Vault → update GH Environment secret → canary plan → revoke old key.

---

## Required GitHub secrets and variables

### R2 (repo secrets — all tofu jobs)

| Name | Purpose |
|------|---------|
| `R2_ACCOUNT_ID` | Cloudflare account id for R2 endpoint |
| `R2_ACCESS_KEY_ID` | R2 access key |
| `R2_SECRET_ACCESS_KEY` | R2 secret key |

### Neon (Environment secrets — per domain)

See table above. **Not** repo-level multi-key dump.

### GCP Workload Identity Federation

| Name | Type | Purpose |
|------|------|---------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | secret/var | WIF provider resource name |
| `GCP_SERVICE_ACCOUNT` | secret/var | Deploy SA email |

Scaffold step in `app-tofu.yml` is `if: false` until WIF exists. Required for Cloud Run, Secret Manager, and **Pub/Sub**.

---

## Platform GCP projects

| Platform | Placeholder `project_id` |
|----------|---------------------------|
| `stawi-dev` | `stawi-cloudrun-dev` |
| `stawi-prod` | `stawi-cloudrun-prod` |

Replace before pilot apply. Pub/Sub resources use the same GCP project as Cloud Run.

---

## Local development

- Never commit credentials.
- Prefer `labs` account and `TF_VAR_neon_api_key` from Vault for experiments.
- Payments/identity prod keys: CI only by default.
- Validate without backend: `tofu init -backend=false && tofu validate`.
