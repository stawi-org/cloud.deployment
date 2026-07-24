# Encrypted credentials

SOPS-encrypted GCP bootstrap metadata (age recipient in repo `.sops.yaml`).

- Path: `credentials/gcp/<account>/<env>/auth.yaml`
- Written by `scripts/bootstrap-gcp-account.sh` (GCP only — no Neon)
- Public registry remains `config/gcp-accounts.yaml` (project/WIF for CI resolve)
- Runtime secrets (DATABASE_URL, etc.) live in **GCP Secret Manager**, not here
- Neon orgs/keys are independent of GCP bootstrap; apps set neon.account separately

Decrypt (operators with private age key only):

```bash
sops -d credentials/gcp/identity/stawi-dev/auth.yaml
```
