# Remote state and credentials

## R2 state backend

OpenTofu remote state is stored in **Cloudflare R2** (S3-compatible), matching `deployment.infra`.

### Shared fragment

Apps use the partial backend config at [`config/r2-backend.hcl`](../config/r2-backend.hcl). The state **key** is supplied at `tofu init` (not in the fragment).

### State key pattern

```
cloud-deployment/apps/<app>/<env>/terraform.tfstate
```

Example:

```
cloud-deployment/apps/hello-edge/stawi-dev/terraform.tfstate
```

### Init example

```bash
export R2_ACCOUNT_ID=...
export AWS_ACCESS_KEY_ID=...      # R2 access key
export AWS_SECRET_ACCESS_KEY=...  # R2 secret key

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
KEY="cloud-deployment/apps/<app>/<env>/terraform.tfstate"

tofu init \
  -backend-config=../../../config/r2-backend.hcl \
  -backend-config="key=${KEY}" \
  -backend-config="endpoints={s3=\"${ENDPOINT}\"}"
```

### Bucket sharing with deployment.infra

The same R2 bucket name as `deployment.infra` (`cluster-tofu-state`) is **intentional**. Isolation is by **key prefix**:

| Repo | Key prefix |
|------|------------|
| `deployment.infra` | (infra-owned prefixes) |
| `cloud.deployment` | `cloud-deployment/apps/<app>/<env>/` |

Do not place this repo’s state under infra key paths.

---

## Required GitHub secrets and variables

### R2 (all OpenTofu plan/apply jobs)

| Name | Type | Purpose |
|------|------|---------|
| `R2_ACCOUNT_ID` | secret | Cloudflare account id for the R2 S3 endpoint |
| `R2_ACCESS_KEY_ID` | secret | R2 API token access key id |
| `R2_SECRET_ACCESS_KEY` | secret | R2 API token secret |

CI maps these to `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for the S3 backend.

### Neon (per account)

Each app’s `app.yaml` sets `neon.account` to a key in [`config/neon-accounts.yaml`](../config/neon-accounts.yaml). CI loads the corresponding GitHub secret and exports it as `NEON_API_KEY` for that job.

| Account key | GitHub secret | Description |
|-------------|----------------|-------------|
| `stawi-org` | `NEON_API_KEY_STAWI_ORG` | Primary Stawi Neon organization |
| `stawi-labs` | `NEON_API_KEY_STAWI_LABS` | Labs / experimental Neon organization |

Add a registry entry and matching GitHub secret when a new Neon organization is needed.

### GCP Workload Identity Federation (Cloud Run + Pub/Sub apply)

Wired as a scaffold step in `.github/workflows/app-tofu.yml` (`google-github-actions/auth`, currently `if: false` until secrets exist):

| Name | Type | Purpose |
|------|------|---------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | secret | Workload identity provider resource name |
| `GCP_SERVICE_ACCOUNT` | secret | GCP service account email to impersonate |

These are required for apply jobs that manage Cloud Run, Secret Manager, and Pub/Sub.

---

## Platform GCP projects

Platform packs set `project_id` used by Cloud Run, Secret Manager, and **Pub/Sub** (same project — apps do not use a separate messaging project).

| Platform | File | Placeholder `project_id` |
|----------|------|---------------------------|
| `stawi-dev` | `platforms/stawi-dev` | `stawi-cloudrun-dev` |
| `stawi-prod` | `platforms/stawi-prod` | `stawi-cloudrun-prod` |

Replace placeholders with real project IDs before pilot apply. CI passes `-var=platform=<env>` so the app root count-switches to the matching platform module.

---

## Local development notes

- Never commit R2 or Neon credentials.
- Prefer short-lived or scoped R2 tokens for local use.
- Validate modules without remote state: `tofu init -backend=false && tofu validate`.
