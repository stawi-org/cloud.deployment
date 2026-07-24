# Account selection and CI credentials (canonical model)

**Date:** 2026-07-24  
**Status:** Accepted  
**Supersedes:** Ad-hoc use of `gcp-identity-prod` / single repo `NEON_API_KEY` / Secret Manager as primary store for Neon org keys.

## Problem we are fixing

Earlier drafts mixed:

- A **single** repo-level `NEON_API_KEY` (wrong when apps pick different Neon orgs)
- GitHub Environments named for **GCP** (`gcp-identity-prod`) holding deploy protection while Neon keys lived on **other** environments (job can only attach **one** environment → wrong secrets)
- Neon org keys optionally forced into a **GCP** project’s Secret Manager (looks like Neon depends on GCP)

That is confusing and does not scale.

## Core rules

1. **Apps select accounts** in `app.yaml` — that is the only linkage between “which Neon org” and “which GCP project”.
2. **Neon and GCP are independent.** Bootstrapping one never requires the other.
3. **A Neon API key is only relevant if the app uses Neon** (`neon.account` is set).
4. **GitHub Environments map 1:1 to credential domains** — no random or dual-purpose env names.
5. **Runtime secrets live in Secret Manager in the selected GCP project**, created by OpenTofu on apply (automatic).
6. **CI deploy credentials** (R2, Neon org API key) are GitHub secrets; **GCP auth is WIF** from the public registry (not a long-lived GCP key in GitHub).

## App declaration

```yaml
# apps/<name>/app.yaml
name: identity-authentication
envs:
  - stawi-prod                 # which env slice of the accounts
gcp:
  account: identity            # key in config/gcp-accounts.yaml
neon:
  account: identity            # key in config/neon-accounts.yaml; omit if no Neon
runtime: cloudrun
```

Resolve:

```
(gcp.account, env)  → project_id, region, WIF provider, deploy SA
(neon.account)      → which Neon org API key GitHub Environment to use
```

If `neon.account` is absent/null → CI does **not** load any Neon key and does **not** configure the Neon provider.

## Registries (git, non-secret)

### `config/gcp-accounts.yaml`

```yaml
accounts:
  identity:
    envs:
      stawi-prod:
        project_id: stawi-identity
        region: europe-west9
        workload_identity_provider: projects/…/providers/github-actions
        deploy_service_account: tofu-deploy@stawi-identity.iam.gserviceaccount.com
        # Optional: GitHub Environment used ONLY for deploy protection (no secrets required)
        # Name MUST be: deploy--{gcp_account}--{env}
        protection_environment: deploy--identity--stawi-prod
```

No Neon fields here.

### `config/neon-accounts.yaml`

```yaml
accounts:
  identity:
    # GitHub Environment name MUST be: neon--{account}
    github_environment: neon--identity
    # secret name inside that environment is always API_KEY
    allowed_deploy_envs: [stawi-prod, stawi-dev]
    neon_org_hint: "Stawi Identity"   # human only
```

No GCP project fields required for the Neon key itself.

## GitHub naming convention (strict)

| Kind | Name pattern | Contains |
|------|----------------|----------|
| **Repository secrets** | fixed names | Shared CI infra only |
| **Neon credential env** | `neon--{neon_account}` | Exactly one secret: `API_KEY` |
| **Deploy protection env** (optional) | `deploy--{gcp_account}--{env}` | **No secrets** — reviewers / wait timers only |

Examples:

- `neon--identity`, `neon--payments`, `neon--labs`
- `deploy--identity--stawi-prod` (optional)

**Forbidden / deprecated:**

- `gcp-identity-prod` as a secrets bucket  
- Single global `NEON_API_KEY` repository secret for all orgs  
- Putting Neon org keys in GCP Secret Manager as the primary CI path  

## What operators set in GitHub

### Repository secrets (all apps / shared)

| Name | Purpose |
|------|---------|
| `R2_ACCOUNT_ID` | OpenTofu state backend |
| `R2_ACCESS_KEY_ID` | OpenTofu state backend |
| `R2_SECRET_ACCESS_KEY` | OpenTofu state backend |

### Environment secrets (per Neon account used by any app)

| Environment | Secret name | Purpose |
|-------------|-------------|---------|
| `neon--identity` | `API_KEY` | Neon org API key for apps with `neon.account: identity` |
| `neon--payments` | `API_KEY` | … when you onboard payments |
| `neon--…` | `API_KEY` | One env per registry key |

Created by `bootstrap-neon-account.sh --sync-github-env` (or manually in UI).

### Not in GitHub

- Database URLs  
- Hydra/cookie/CSRF material  
- Google OAuth (optional TF vars → SM on apply)  
- GCP service account keys  

## CI job model (seamless)

For each matrix cell `(app, env)`:

1. Resolve context from registries.  
2. Set job **environment** to:
   - If app has `neon.account`: **`neon--{neon.account}`** (loads `API_KEY`)  
   - Else if `protection_environment` set: that env (no secrets)  
   - Else: no environment  
3. Export `TF_VAR_neon_api_key` from `secrets.API_KEY` **only if** neon.account is set.  
4. Authenticate to GCP via **WIF** using registry fields for `(gcp.account, env)`.  
5. `tofu plan|apply` with `project_id` / `region` from registry.  

OpenTofu writes **runtime** secrets into **Secret Manager in that GCP project** automatically.

Optional: also attach protection rules on `deploy--…` by using a workflow `environment` that is only protection — but GitHub allows only one environment per job. Therefore:

- **Credential env = Neon env** when Neon is needed (primary).  
- Deploy protection for GCP-only can use `deploy--…` when there is no Neon.  
- When both Neon and GCP protection are desired, put protection rules on **`neon--{account}`** (reviewers on the Neon credential environment) or accept protection on the Neon env only.

This avoids two environments fighting for secrets.

## Secret Manager (automatic)

In the **selected GCP project** for `(gcp.account, env)`:

| Secret | How |
|--------|-----|
| `{app}-database-url` | OpenTofu from Neon module output |
| Generated app crypto | OpenTofu `random_password` → SM |
| Runtime SA access | OpenTofu IAM |

No manual SM copy for normal deploys.

## Bootstraps (unchanged separation)

| Script | Writes | Never does |
|--------|--------|------------|
| `bootstrap-gcp-account.sh` | GCP WIF/SA, `gcp-accounts.yaml`, SOPS `credentials/gcp/...` | Neon keys |
| `bootstrap-neon-account.sh` | SOPS `credentials/neon/...`, registry metadata, GH env `neon--{account}` + `API_KEY` | GCP projects |

## App without Neon

```yaml
gcp:
  account: platform
# neon: omitted
```

CI: no Neon key; WIF to platform project; no `neon--*` environment.

## Migration from old names

| Old | New |
|-----|-----|
| `neon-identity` + secret `NEON_API_KEY` | `neon--identity` + secret `API_KEY` |
| `gcp-identity-prod` (secrets) | Drop secrets; optional `deploy--identity--stawi-prod` protection-only |
| Repo `NEON_API_KEY` | Remove; use per-account env `neon--{account}` |

## Success criteria

- Adding a Neon org = one registry key + one GH env `neon--{key}` + one `API_KEY` secret.  
- Adding a GCP project = one registry slice + WIF bootstrap; no new GH secret.  
- App matrix never loads Neon credentials for apps that do not select Neon.  
- No job depends on two GH environments for secrets.  
- Operators never hand-maintain DATABASE_URL in SM.  
