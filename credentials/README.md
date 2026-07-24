# Encrypted credentials

SOPS age recipient is in repo `.sops.yaml` (encrypt-only on bootstrap machines).

## GCP (`scripts/bootstrap-gcp-account.sh`)

- Path: `credentials/gcp/<account>/<env>/auth.yaml`
- Non-secret project/WIF also written to `config/gcp-accounts.yaml` for CI resolve
- Does **not** configure Neon

## Neon (`scripts/bootstrap-neon-account.sh`)

- Path: `credentials/neon/<account>/auth.yaml`
- Contains org API key (SOPS). Used by operators / optional CI decrypt.
- Non-secret registry: `config/neon-accounts.yaml`
- CI preferred: GitHub Environment `NEON_API_KEY` (`--sync-github-env`) or Secret Manager (configured separately per deploy GCP project)
- Apps link Neon↔GCP only via `app.yaml` (`neon.account` + `gcp.account`)

## Runtime secrets

`DATABASE_URL` and app secrets live in **GCP Secret Manager**, not git.

```bash
sops -d credentials/gcp/identity/stawi-dev/auth.yaml
sops -d credentials/gcp/identity/stawi-prod/auth.yaml
sops -d credentials/neon/identity/auth.yaml
```
