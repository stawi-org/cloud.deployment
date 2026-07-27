# Encrypted credentials

SOPS age recipient is in repo `.sops.yaml`. CI uses repository secret `SOPS_AGE_KEY`.

## GCP
- `credentials/gcp/<account>/<env>/auth.yaml` — from `scripts/bootstrap-gcp-account.sh`
- Non-secret project/WIF/**region** also in `config/gcp-accounts.yaml`
- **Region source of truth:** `gcp-accounts.yaml` (CI prefers registry over SOPS `auth.region`)
- After a region migration, optionally re-encrypt SOPS so it matches:
  `sops set credentials/gcp/<account>/<env>/auth.yaml '["auth"]["region"]' '"europe-west1"'`

## Neon (independent of GCP)
- `credentials/neon/<account>/auth.yaml` — from `scripts/bootstrap-neon-account.sh`
- Contains org API key (SOPS). CI decrypts when app has `neon.account`.
- Non-secret registry: `config/neon-accounts.yaml`
- Apps link Neon↔GCP only via `app.yaml` (`neon.account` + `gcp.account`)

Decrypt (private age key required):

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-...'
sops -d credentials/neon/identity/auth.yaml
sops -d credentials/gcp/identity/stawi-prod/auth.yaml
```
