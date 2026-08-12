# Decentralized Cloud Run image ship

**Platform** (OpenTofu in this repo) and **product binary** (service repos) are split.

| Concern | Owner | How often |
|---------|--------|-----------|
| Project, runtime SA, secrets, Neon, Pub/Sub, OIDC env, migrate **job definition** | `cloud.deployment` | Rare |
| Which container image is live + migrate **execution** | **Service repo** on `v*.*.*` tag | Every release |

Cloud Run does **not** auto-pull new tags. Shipping is explicit: release → WIF → `gcloud run` update.

## Policy (hard rules)

| Rule | Value |
|------|--------|
| **Image registry** | **Public GHCR only** — `ghcr.io/antinvestor/...` |
| **Cloud Run region** | **`europe-west1` only** (Paris/`europe-west9` retired) |
| **Artifact Registry** | **Not used** for service images (no `*.pkg.dev` mirrors) |
| **OpenTofu** | Ignores image on service/job (`lifecycle.ignore_changes`) |

The reusable workflow enforces registry + region:

[`antinvestor/common/.github/workflows/cloudrun-ship.yml`](https://github.com/antinvestor/common/blob/main/.github/workflows/cloudrun-ship.yml)

- Default `region: europe-west1`
- Fails if `region` is `europe-west9` (or any non–west1 value)
- Fails if image is not `ghcr.io/...` (rejects `*.pkg.dev` / `gcr.io`)

## Architecture

```text
antinvestor/service-profile  tag v1.53.5
  ├─ docker-release → ghcr.io/antinvestor/service-profile:v1.53.5  (public)
  └─ cloudrun-ship
       WIF: github-ship → cloudrun-ship@PROJECT
       region: europe-west1 (fixed)
       1. update {app}-migrate job image
       2. execute migrate --wait
       3. update Cloud Run service image → new revision
```

## Identity (stawi-prod)

| GitHub repo | GHCR image | Cloud Run service | Migrate job |
|-------------|------------|-------------------|-------------|
| `antinvestor/service-profile` | `ghcr.io/antinvestor/service-profile` | `identity-profile` | `identity-profile-migrate` |
| `antinvestor/service-authentication` | `ghcr.io/antinvestor/service-authentication` | `identity-authentication` | `identity-authentication-migrate` |
| `antinvestor/service-authentication` | `ghcr.io/antinvestor/service-authentication-tenancy` | `identity-tenancy` | `identity-tenancy-migrate` |
| `antinvestor/service-fintech` | `ghcr.io/antinvestor/service-fintech-identity` | `identity-identity` | `identity-identity-migrate` |

```text
project_id:                   stawi-identity
region:                       europe-west1
ship_service_account:         cloudrun-ship@stawi-identity.iam.gserviceaccount.com
workload_identity_provider:   projects/721554040672/locations/global/workloadIdentityPools/github/providers/github-ship
```

## Platform (stawi-prod)

| GitHub repo | GHCR image | Cloud Run service |
|-------------|------------|-------------------|
| `antinvestor/service-profile` (devices package) | `ghcr.io/antinvestor/service-profile-devices` | `platform-devices` |
| `antinvestor/service-profile` (settings) | `ghcr.io/antinvestor/service-profile-settings` | `platform-settings` |
| `antinvestor/service-profile` (geolocation) | `ghcr.io/antinvestor/service-profile-geolocation` | `platform-geolocation` |
| `antinvestor/service-profile` (chatagent) | `ghcr.io/antinvestor/service-profile-chatagent` | `platform-chat-agent` |
| `antinvestor/service-files` | `ghcr.io/antinvestor/service-files` | `platform-files` |
| `stawi-opportunities/opportunities` (`apps/calendar`) | `ghcr.io/stawi-opportunities/opportunities-calendar` | `platform-calendar` |

```text
project_id:                   stawi-platform
region:                       europe-west1
ship_service_account:         cloudrun-ship@stawi-platform.iam.gserviceaccount.com
workload_identity_provider:   projects/305282281906/locations/global/workloadIdentityPools/github/providers/github-ship
```

## Bootstrap (once per GCP project)

```bash
./scripts/bootstrap-cloudrun-ship.sh \
  --project stawi-identity \
  --project-number 721554040672 \
  --runtime-sa identity-profile,identity-tenancy,identity-identity,identity-authentication \
  --ship-repo antinvestor/service-profile,antinvestor/service-authentication,antinvestor/service-fintech
```

- **tofu-deploy** WIF stays locked to `stawi-org/cloud.deployment`.
- **github-ship** only allowlists listed antinvestor service repos.
- Does **not** create Artifact Registry or grant AR roles.

## GHCR must stay public

Cloud Run pulls `ghcr.io` anonymously — packages must be public.

| Concern | How |
|---------|-----|
| New releases | `docker-release.yml` sets package visibility public after push |
| Existing private packages | `scripts/make-ghcr-public.sh` or `make-ghcr-public.yml` on `antinvestor/common` |

```bash
gh auth refresh -h github.com -s read:packages,write:packages
./scripts/make-ghcr-public.sh
```

## Caller contract (`release.yaml`)

```yaml
uses: antinvestor/common/.github/workflows/cloudrun-ship.yml@main
with:
  image: ghcr.io/antinvestor/service-profile:${{ github.ref_name }}
  service: identity-profile
  project_id: stawi-identity
  region: europe-west1   # optional; defaults to europe-west1; west9 is rejected
  migrate_job: identity-profile-migrate
  ship_service_account: cloudrun-ship@stawi-identity.iam.gserviceaccount.com
  workload_identity_provider: projects/721554040672/locations/global/workloadIdentityPools/github/providers/github-ship
```

Do **not** pass `*.pkg.dev` images or `region: europe-west9`.

## Rollback

```bash
gcloud run services update-traffic identity-profile \
  --region=europe-west1 --project=stawi-identity \
  --to-revisions=PREVIOUS_REVISION=100
```

Or re-ship a previous semver tag via the service repo workflow.

## What still needs cloud.deployment apply

- New env vars, secrets, scaling, Pub/Sub topics
- First-time service create
- Neon / IAM / WIF bootstrap

Image-only releases never need a monorepo pin PR.
