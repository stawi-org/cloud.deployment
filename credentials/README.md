# Encrypted credentials

## GCP
- `credentials/gcp/<account>/<env>/auth.yaml` — from `scripts/bootstrap-gcp-account.sh`
- Non-secret project/WIF also in `config/gcp-accounts.yaml`

## Neon (independent of GCP)
- `credentials/neon/<account>/auth.yaml` — from `scripts/bootstrap-neon-account.sh`
- Contains org API key (SOPS). Used by operators / optional CI decrypt.
- Non-secret registry: `config/neon-accounts.yaml`
- CI preferred: GitHub Environment `NEON_API_KEY` (`--sync-github-env`) or Secret Manager (configured separately per deploy GCP project)
- Apps link Neon↔GCP only via `app.yaml` (`neon.account` + `gcp.account`)

Decrypt (private age key required):

```bash
sops -d credentials/neon/identity/auth.yaml
```
