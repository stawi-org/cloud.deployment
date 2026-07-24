# Account selection and CI credentials (canonical model)

**Date:** 2026-07-24  
**Status:** Accepted (updated)  
**Supersedes:** GitHub Environment–based Neon/GCP credentials (`neon--*`, `deploy--*`).

## Problem we are fixing

Earlier drafts mixed:

- A **single** repo-level `NEON_API_KEY` (wrong when apps pick different Neon orgs)
- GitHub Environments named for **GCP** holding deploy protection while Neon keys lived on **other** environments
- Dual-purpose env names and optional SM storage for Neon org keys on GCP

That is confusing and does not scale. Credentials already live in **SOPS files** under `credentials/` — CI should use those.

## Core rules

1. **Apps select accounts** in `app.yaml` — that is the only linkage between “which Neon org” and “which GCP project”.
2. **Neon and GCP are independent.** Bootstrapping one never requires the other.
3. **A Neon API key is only relevant if the app uses Neon** (`neon.account` is set).
4. **Deploy credentials live in SOPS** under `credentials/{gcp,neon}/…`, decrypted with repository secret `SOPS_AGE_KEY`.
5. **Runtime secrets live in Secret Manager** in the selected GCP project, created by OpenTofu on apply.
6. **GCP auth is WIF** (no long-lived GCP key in GitHub).
7. **No per-account GitHub Environments** for secrets (`neon--*`, `deploy--*` not required).

## App declaration

```yaml
# apps/<name>/app.yaml
name: identity-authentication
envs:
  - stawi-prod
gcp:
  account: identity
neon:
  account: identity            # omit if no Neon
runtime: cloudrun
```

Resolve:

```
(gcp.account, env)  → credentials/gcp/<account>/<env>/auth.yaml + registry mirror
(neon.account)      → credentials/neon/<account>/auth.yaml
```

## Registries (git, non-secret)

### `config/gcp-accounts.yaml`

Public mirror of project_id, region, WIF, deploy SA, labels, `sops_auth_path`.

### `config/neon-accounts.yaml`

Policy: allowed_deploy_envs, allowed_app_prefixes, org hint, `sops_auth_path`.

## What operators set in GitHub

| Name | Purpose |
|------|---------|
| `R2_ACCOUNT_ID` | OpenTofu state (`cloud-tofu-state`) |
| `R2_ACCESS_KEY_ID` | OpenTofu state |
| `R2_SECRET_ACCESS_KEY` | OpenTofu state |
| `SOPS_AGE_KEY` | Private age key for `credentials/**` |

## CI job model

For each matrix cell `(app, env)`:

1. Resolve context from registries.  
2. Decrypt SOPS credentials (`load-sops-credentials.sh`).  
3. Export `TF_VAR_neon_api_key` **only if** `neon.account` is set.  
4. Authenticate to GCP via **WIF**.  
5. `tofu plan|apply` with state key `cloud-deployment/apps/<app>/<env>/terraform.tfstate` in bucket `cloud-tofu-state`.

## Bootstraps

| Script | Writes | Never does |
|--------|--------|------------|
| `bootstrap-gcp-account.sh` | GCP WIF/SA, registry, SOPS `credentials/gcp/...` | Neon keys |
| `bootstrap-neon-account.sh` | SOPS `credentials/neon/...`, registry metadata | GCP projects |

## Success criteria

- Adding a Neon org = one registry key + one SOPS file; no new GH Environment.  
- Adding a GCP project = bootstrap + SOPS file + registry; no new GH secret (WIF).  
- App matrix never loads Neon credentials for apps that do not select Neon.  
- Operators never hand-maintain DATABASE_URL in SM for normal deploys.  
- Cost defaults: Cloud Run scale-to-zero, Neon autosuspend + low CU caps.  
