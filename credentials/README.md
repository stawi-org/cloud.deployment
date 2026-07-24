# Encrypted credentials

SOPS age recipient is in repo `.sops.yaml`. CI uses repository secret `SOPS_AGE_KEY`.

- Path: `credentials/gcp/<account>/<env>/auth.yaml`
- Written by `scripts/bootstrap-gcp-account.sh` (GCP only — no Neon)
- Public registry remains `config/gcp-accounts.yaml` (project/WIF for CI resolve)
- Runtime secrets (DATABASE_URL, etc.) live in **GCP Secret Manager**, not here
- Neon orgs/keys are independent of GCP bootstrap; apps set neon.account separately

Decrypt (operators with private age key only):

```bash
sops -d credentials/gcp/identity/stawi-dev/auth.yaml
```
