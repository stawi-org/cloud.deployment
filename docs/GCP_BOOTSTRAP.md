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
| 5 | PR: update `config/gcp-accounts.yaml` for `--account` / `--env` |
| 6 | PR: SOPS-encrypt `credentials/gcp/<account>/<env>/auth.yaml` (age key in `.sops.yaml`) |

**Neon is not part of this script.** Neon organizations and API keys are created independently. The only linkage is per app: `app.yaml` chooses `gcp.account` and `neon.account` separately.

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
  --region europe-west1
```

Neon (separate step, not this script): create the Neon org/API key elsewhere; register it in `config/neon-accounts.yaml` / Secret Manager or GH Environment as documented in [BACKEND.md](BACKEND.md). Apps link GCP↔Neon only via `app.yaml`.

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

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `no matching creation rules found` (sops) | Need current script: `sops encrypt --filename-override credentials/gcp/...` (not bare `sops -e /tmp/...`) |
| `sops encrypt preflight failed` | Update clone so `.sops.yaml` has `credentials/gcp/` rules; install sops ≥ 3.11 |
| WIF works but plan can’t pull images | Deploy SA has `roles/artifactregistry.reader` after latest bootstrap |
| Want apply protection env | Create GH Environment named as in registry (`github_environment`, e.g. `gcp-identity-dev`) in UI — same PAT limits as Neon (often need Administration for create via API) |
| Accidental Neon flag | Script rejects `--neon-api-key`; use [NEON_BOOTSTRAP.md](NEON_BOOTSTRAP.md) |

## Improvements baked into the script

- SOPS encrypt with `--filename-override` (same fix as Neon bootstrap)
- Preflight encrypt before long GCP work
- yq-only registry edit (no PyYAML)
- Extra deploy SA roles (Artifact Registry, logging)
- Idempotent WIF→SA binding check
- `sops_auth_path` + labels written on registry slice
- Clear post-merge next steps (resolve-app-context, Neon separate)

## Related

- [BACKEND.md](BACKEND.md)
- [NEON_BOOTSTRAP.md](NEON_BOOTSTRAP.md)
- [IDENTITY_GREENFIELD.md](IDENTITY_GREENFIELD.md)
- Multi-account design: `docs/superpowers/specs/2026-07-24-multi-account-platform-identity-greenfield.md`

## Neon (separate)

Do **not** pass Neon keys to this script. Use [NEON_BOOTSTRAP.md](NEON_BOOTSTRAP.md) / `scripts/bootstrap-neon-account.sh`.
