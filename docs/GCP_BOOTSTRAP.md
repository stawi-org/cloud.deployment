# GCP account bootstrap

GCP bootstrap is **independent of Neon**. It never writes Neon keys.

## What it does

1. Enables required APIs (Run, Secret Manager, Pub/Sub, IAM, STS, …).  
2. Creates deploy service account + WIF pool/provider for `stawi-org/cloud.deployment`.  
3. Grants deploy SA roles for Cloud Run, SM, Pub/Sub, service accounts.  
4. Grants human operator `bwire517@gmail.com` full project control so one account can manage every bootstrapped domain project (console, gcloud, IAM, secrets, Run, logs). Prefers **Owner**; if the org policy blocks external Owners (`ORG_MUST_INVITE_EXTERNAL_OWNERS`), falls back to **Editor + projectIamAdmin + domain admin roles**. Re-run with `--iam-only` to refresh existing projects.
5. Updates `config/gcp-accounts.yaml` (public mirror).  
6. Writes SOPS-encrypted `credentials/gcp/<account>/<env>/auth.yaml`.  

If `--account` / `--env` are **not** already in the registry, bootstrap **creates** them in the PR (defaults: `owners: [platform]`, `sensitivity: medium`). You do not need to edit `gcp-accounts.yaml` by hand first.

Existing clones (including `~/cloud.deployment` and `--repo-path`) are **always** `git fetch` + hard-reset to `origin/main` (or `--base-branch`) so registry/script fixes land without a manual pull. Dirty trees are stashed first.

CI uses **WIF** from the SOPS file (or registry mirror) — no long-lived GCP keys in GitHub.

## Prerequisites

- `gcloud` authenticated as project owner/editor  
- Cloud Shell or local with project access  
- `sops`, `yq`, `jq`, `git`  
- Public age key already in repo `.sops.yaml`  

## Usage

```bash
# Existing account
./scripts/bootstrap-gcp-account.sh \
  --account identity \
  --env stawi-prod \
  --project stawi-identity \
  --region europe-west1 \
  --repo-path "$PWD"

# New domain (auto-registers accounts.operations + envs.stawi-prod)
./scripts/bootstrap-gcp-account.sh \
  --account operations \
  --env stawi-prod \
  --project stawi-operations \
  --region europe-west1
```

## After bootstrap

1. Merge the PR.  
2. Confirm repository secrets: `R2_*` + `SOPS_AGE_KEY`.  
3. Test resolve:

```bash
./.github/scripts/resolve-app-context.sh identity-authentication stawi-prod
```

Optional apply protection (required reviewers) can be added in GitHub **repository rules / branch protection** or a single shared environment if desired — not per `deploy--{account}--{env}` credential envs.

## Related

- [GITHUB_SECRETS.md](GITHUB_SECRETS.md)  
- [BACKEND.md](BACKEND.md)  
- [NEON_BOOTSTRAP.md](NEON_BOOTSTRAP.md)  
