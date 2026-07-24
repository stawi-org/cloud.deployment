# Neon account bootstrap

Neon is **independent of GCP**. This script never touches GCP projects.

## What it does

1. Validates the org API key (best-effort `GET /users/me`).  
2. Writes SOPS-encrypted `credentials/neon/<account>/auth.yaml`.  
3. Updates non-secret metadata on `config/neon-accounts.yaml` (`sops_auth_path`, org hint).  
4. Opens a PR (optional).

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

./scripts/bootstrap-neon-account.sh --account identity

./scripts/bootstrap-neon-account.sh --account payments \
  --api-key "$API_KEY" \
  --org-hint "Stawi Payments" \
  --repo-path "$PWD"
```

| Flag | Purpose |
|------|---------|
| `--account` | Key in `config/neon-accounts.yaml` (required) |
| `--api-key` | Org API key (or env `API_KEY` / `NEON_ORG_API_KEY`) |
| `--org-hint` | Human label |
| `--metadata-only` | Registry metadata without writing API key |
| `--force-repo-write` | Overwrite existing SOPS file |
| `--sync-github-env` | **Deprecated no-op** — CI no longer uses `neon--*` environments |

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
