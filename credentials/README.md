# Encrypted credentials

SOPS age recipient is in repo `.sops.yaml`. CI uses repository secret `SOPS_AGE_KEY`.

## GCP
- `credentials/gcp/<account>/<env>/auth.yaml` — from `scripts/bootstrap-gcp-account.sh`
- Non-secret project/WIF also in `config/gcp-accounts.yaml`

## Neon (independent of GCP)
- `credentials/neon/<account>/auth.yaml` — from `scripts/bootstrap-neon-account.sh`
- Contains org API key (SOPS). CI decrypts when app has `neon.account`.
- Non-secret registry: `config/neon-accounts.yaml`
- Apps link Neon↔GCP only via `app.yaml` (`neon.account` + `gcp.account`)

### Domain keys in use

| Account | Org id | Used by |
|---------|--------|---------|
| `identity` | `org-rapid-mountain-41505493` | `identity-*` apps only |
| `platform` | `org-calm-cell-68997035` | `platform-*` apps only |

Platform apps must never reuse the identity Neon key. See `docs/DEPLOY_PLATFORM.md`.

Decrypt (private age key required):

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-...'
sops -d credentials/neon/identity/auth.yaml
sops -d credentials/neon/platform/auth.yaml
sops -d credentials/gcp/identity/stawi-prod/auth.yaml
sops -d credentials/gcp/platform/stawi-prod/auth.yaml
```
