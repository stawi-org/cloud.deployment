# Bootstrap a GCP account (Cloud Shell)

Configure a GCP project for **cloud.deployment** the same way `deployment.infra` onboards workers: **WIF + deploy SA**, then a **GitHub PR** that updates the public registry and stores **SOPS-encrypted** auth metadata.

The multi-account plan stays intact:

- Apps still set `gcp.account` + `neon.account` in `app.yaml`
- CI still uses `resolve-app-context.sh`
- Runtime secrets stay in **Secret Manager** (not git)
- Registry (`config/gcp-accounts.yaml`) holds non-secret project/WIF fields for resolve

## Script

[`scripts/bootstrap-gcp-account.sh`](../scripts/bootstrap-gcp-account.sh)

## What it does

| Step | Action |
|------|--------|
| 1 | Enable APIs: Cloud Run, Secret Manager, Pub/Sub, IAM, STS, … |
| 2 | Create WIF pool/provider bound to `stawi-org/cloud.deployment` |
| 3 | Create SA `tofu-deploy@PROJECT` + roles (Run, SM, Pub/Sub, SA admin/user) |
| 4 | Bind GitHub OIDC → `roles/iam.workloadIdentityUser` |
| 5 | Optional: write Neon org API key to SM secret `neon-org-api-key` |
| 6 | PR: update `config/gcp-accounts.yaml` for `--account` / `--env` |
| 7 | PR: SOPS-encrypt `credentials/gcp/<account>/<env>/auth.yaml` (age key in `.sops.yaml`) |

Safe to re-run (additive IAM). Skips git if already onboarded unless `--force-repo-write`.

## Cloud Shell

```bash
# Upload the script, or:
curl -fsSL https://raw.githubusercontent.com/stawi-org/cloud.deployment/main/scripts/bootstrap-gcp-account.sh \
  -o bootstrap-gcp-account.sh
chmod +x bootstrap-gcp-account.sh

export GITHUB_TOKEN=ghp_xxxxxxxx   # repo (or fine-grained Contents + PR)

./bootstrap-gcp-account.sh \
  --project stawi-identity-dev \
  --account identity \
  --env stawi-dev \
  --region europe-west1 \
  --neon-api-key "$NEON_ORG_API_KEY"   # optional but recommended
```

| Flag | Meaning |
|------|---------|
| `--account` | Key in `config/gcp-accounts.yaml` (`identity`, `payments`, …) |
| `--env` | `stawi-dev` or `stawi-prod` |
| `--iam-only` | GCP only, no git |
| `--no-push` | Commit in worktree only |
| `--force-repo-write` | Refresh PR even if already on main |

## After merge

```bash
./.github/scripts/resolve-app-context.sh identity-authentication stawi-dev
# project_id / WIF should match the bootstrapped project
```

Apps with `gcp.account: identity` will deploy into that project. CI fetches Neon org key from Secret Manager when WIF works.

## SOPS

- Public age recipient: `.sops.yaml` (same key family as `deployment.infra`)
- Path: `credentials/gcp/<account>/<env>/auth.yaml`
- Bootstrap machine needs **only** the public key (encrypt)
- Decrypt requires the private age key (operators / CI with sops key — not required for normal cloud.deployment plan/apply via WIF)

## Related

- [BACKEND.md](BACKEND.md)
- [IDENTITY_GREENFIELD.md](IDENTITY_GREENFIELD.md)
- Multi-account design: `docs/superpowers/specs/2026-07-24-multi-account-platform-identity-greenfield.md`
