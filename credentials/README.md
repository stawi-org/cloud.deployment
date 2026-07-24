# Encrypted credentials

SOPS age recipient is in repo `.sops.yaml` (encrypt-only on bootstrap machines).

**CI** uses one repository secret: `SOPS_AGE_KEY` (private age key) to decrypt these files at plan/apply time. No `neon--*` or `deploy--*` GitHub Environments.

## GCP (`scripts/bootstrap-gcp-account.sh`)

- Path: `credentials/gcp/<account>/<env>/auth.yaml`
- Contains: project_id, region, WIF provider resource, deploy service account
- Non-secret project/WIF also written to `config/gcp-accounts.yaml` for resolve/display
- Does **not** configure Neon

## Neon (`scripts/bootstrap-neon-account.sh`)

- Path: `credentials/neon/<account>/auth.yaml`
- Contains org API key (SOPS). Loaded only when `app.yaml` has `neon.account`
- Non-secret registry: `config/neon-accounts.yaml`
- Apps link Neon↔GCP only via `app.yaml` (`neon.account` + `gcp.account`)

## Runtime secrets

`DATABASE_URL` and app secrets live in **GCP Secret Manager**, not git. OpenTofu writes them on apply.

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-...'
sops -d credentials/gcp/identity/stawi-prod/auth.yaml
sops -d credentials/neon/identity/auth.yaml

# Local deploy helper
eval "$(./.github/scripts/load-sops-credentials.sh identity-authentication stawi-prod)"
```
