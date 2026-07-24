# Decentralized Cloud Run image ship

**Platform** (OpenTofu in this repo) and **product binary** (service repos) are split.

| Concern | Owner | How often |
|---------|--------|-----------|
| Project, runtime SA, secrets, Neon, Pub/Sub, OIDC env, migrate **job definition** | `cloud.deployment` | Rare |
| Which container image is live + migrate **execution** | **Service repo** on `v*.*.*` tag | Every release |

Cloud Run does **not** auto-pull new tags. Shipping is explicit: release → WIF → `gcloud run` update.

## Architecture

```text
antinvestor/service-profile  tag v1.53.5
  ├─ docker-release (GHCR)
  └─ cloudrun-ship (reusable, antinvestor/common)
       WIF provider: github-ship
       SA:           cloudrun-ship@stawi-identity.iam.gserviceaccount.com
       1. update {app}-migrate job image
       2. execute migrate --wait
       3. update Cloud Run service image  → new revision
```

OpenTofu **ignores** container image on services and migrate jobs (`lifecycle.ignore_changes`), so infra applies never revert a ship.

## Identity domain (stawi-prod)

| GitHub repo | GHCR image | Cloud Run service | Migrate job |
|-------------|------------|-------------------|-------------|
| `antinvestor/service-profile` | `ghcr.io/antinvestor/service-profile` | `identity-profile` | `identity-profile-migrate` |
| `antinvestor/service-authentication` | `ghcr.io/antinvestor/service-authentication` | `identity-authentication` | `identity-authentication-migrate` |
| `antinvestor/service-authentication` | `ghcr.io/antinvestor/service-authentication-tenancy` | `identity-tenancy` | `identity-tenancy-migrate` |
| `antinvestor/service-fintech` | `ghcr.io/antinvestor/service-fintech-identity` | `identity-identity` | `identity-identity-migrate` |

Shared values (public, not secrets):

```text
project_id:                   stawi-identity
region:                       europe-west9
ship_service_account:         cloudrun-ship@stawi-identity.iam.gserviceaccount.com
workload_identity_provider:   projects/721554040672/locations/global/workloadIdentityPools/github/providers/github-ship
```

## Bootstrap (once per GCP project)

```bash
./scripts/bootstrap-cloudrun-ship.sh \
  --project stawi-identity \
  --project-number 721554040672 \
  --runtime-sa identity-profile,identity-tenancy,identity-identity,identity-authentication \
  --ship-repo antinvestor/service-profile,antinvestor/service-authentication,antinvestor/service-fintech
```

- **tofu-deploy** WIF provider stays locked to `stawi-org/cloud.deployment`.
- **github-ship** provider only allows listed antinvestor service repos.

## Reusable workflow

[`antinvestor/common/.github/workflows/cloudrun-ship.yml`](https://github.com/antinvestor/common/blob/main/.github/workflows/cloudrun-ship.yml)

Caller supplies image, service, project, region, WIF, ship SA, optional migrate job.

Service allowlist (default): identity Frame apps + platform (`platform-devices`, `platform-settings`, `platform-geolocation`, `platform-files`). Pass `allowed_services` to override.

## Adding a new Frame service

1. Apply app stack in this repo (service + migrate job + messaging exist).
2. Grant ship SA `roles/iam.serviceAccountUser` on the new runtime SA (re-run bootstrap with updated `--runtime-sa`).
3. Add repo to WIF allowlist (`--ship-repo`) if new.
4. In the service repo `release.yaml`, add a `ship` job calling `cloudrun-ship.yml` after `docker`.
5. Prefer semver tags; avoid shipping `:latest` to prod.

## Rollback

Re-run ship for a previous tag, or:

```bash
gcloud run services update-traffic identity-profile \
  --region=europe-west9 --project=stawi-identity \
  --to-revisions=PREVIOUS_REVISION=100
```

## What still requires cloud.deployment apply

- New env vars (e.g. queue OIDC), secrets, scaling, Pub/Sub topics
- First-time service create
- Neon / IAM / WIF bootstrap changes

Image-only releases never need a monorepo pin PR.
