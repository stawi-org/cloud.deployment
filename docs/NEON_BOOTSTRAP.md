# Neon account bootstrap

Neon is **independent of GCP**. This script never touches GCP projects.

## What it does

1. Syncs the checkout to latest `origin/main` (fetch + hard-reset; stashes dirt).  
2. Validates the org API key (best-effort `GET /users/me`).  
3. Writes SOPS-encrypted `credentials/neon/<account>/auth.yaml`.  
4. Updates non-secret metadata on `config/neon-accounts.yaml` (`sops_auth_path`, org hint).  
   If `--account` is **missing** from the registry, it is **auto-created** (defaults:  
   `owners: [platform]`, `sensitivity: medium`, `allowed_app_prefixes: [<account>-]`).  
5. Opens a PR (optional).

CI decrypts the SOPS file with repository secret **`SOPS_AGE_KEY`**. No GitHub Environments.

## Prerequisites

- Neon org + org API key from console  
- `sops`, `yq`, `jq`, `git`, `curl`  
- Age private key only needed to **decrypt**; bootstrap **encrypts** with public key in `.sops.yaml`  
- `GITHUB_TOKEN` if pushing a PR from Cloud Shell  

## Usage

```bash
export API_KEY=napi_xxx
export GITHUB_TOKEN=ghp_xxx   # for push/PR

./scripts/bootstrap-neon-account.sh --account identity \
  --api-key "$API_KEY" \
  --org-hint "Stawi Identity" \
  --org-id org-rapid-mountain-41505493

# Platform domain (devices/settings/geolocation/files) — use this for all platform-* apps
./scripts/bootstrap-neon-account.sh --account platform \
  --api-key "$API_KEY" \
  --org-hint "Stawi Platform" \
  --org-id org-calm-cell-68997035

./scripts/bootstrap-neon-account.sh --account payments \
  --api-key "$API_KEY" \
  --org-hint "Stawi Payments" \
  --repo-path "$PWD"

# New domain (auto-registers accounts.operations if missing)
./scripts/bootstrap-neon-account.sh --account operations \
  --api-key "$API_KEY" \
  --org-hint "Stawi Operations" \
  --org-id org-xxxx
```

| Flag | Purpose |
|------|---------|
| `--account` | Key in `config/neon-accounts.yaml` (required; auto-created if new) |
| `--api-key` | Org API key (or env `API_KEY` / `NEON_ORG_API_KEY`) |
| `--org-hint` | Human label |
| `--org-id` | Neon org id (metadata) |
| `--metadata-only` | Registry metadata without writing API key |
| `--force-repo-write` | Overwrite existing SOPS file |

## After bootstrap

1. Merge the PR so `credentials/neon/<account>/auth.yaml` is on `main`.  
2. Confirm GitHub repository secret `SOPS_AGE_KEY` is set.  
3. Any app with `neon.account: <key>` will load that key on plan/apply.

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-...'
./.github/scripts/load-sops-credentials.sh identity-authentication stawi-prod
```

## Related

- [GITHUB_SECRETS.md](GITHUB_SECRETS.md)  
- [BACKEND.md](BACKEND.md)  
- [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md) (separate)  
