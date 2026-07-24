# Platform domain deploy (Cloud Run)

**GCP project:** `stawi-platform` (305282281906) · **region:** `europe-west9`  
**Account key:** `platform` in `config/gcp-accounts.yaml`

## Apps

| App | Image (bootstrap) | Source |
|-----|-------------------|--------|
| `platform-devices` | `ghcr.io/antinvestor/service-profile-devices` | service-profile `apps/devices` |
| `platform-settings` | `ghcr.io/antinvestor/service-profile-settings` | service-profile `apps/settings` |
| `platform-geolocation` | `ghcr.io/antinvestor/service-profile-geolocation` | service-profile `apps/geolocation` |
| `platform-files` | `ghcr.io/antinvestor/service-files` | service-files `apps/default` |

## Dependencies on identity

| Dependency | Where |
|------------|--------|
| Hydra OIDC | `stawi-identity` Cloud Run `identity-oauth2-hydra` |
| Keto read/write | `stawi-identity` keto-read / keto-write |
| `hydra-webhook-psk` | Copied into `stawi-platform` Secret Manager |

`tofu-deploy@stawi-platform` has `roles/run.viewer` on `stawi-identity` so OpenTofu can resolve Hydra/Keto URIs.

## Neon

Apps currently use `neon.account: identity` (shared Neon org) until a dedicated **platform** Neon org + SOPS file is bootstrapped:

```bash
./scripts/bootstrap-neon-account.sh --account platform --api-key "$NEON_API_KEY"
# then set neon.account: platform and neon_org_id in neon-accounts.yaml
```

## Ship (decentralized)

```
ship_service_account:       cloudrun-ship@stawi-platform.iam.gserviceaccount.com
workload_identity_provider: projects/305282281906/locations/global/workloadIdentityPools/github/providers/github-ship
```

Service repos call `antinvestor/common` `cloudrun-ship.yml` with the platform service names after docker-release.

## First apply (per app)

```bash
# CI: merge apps/platform-* and workflow_dispatch app-apply
# Or local (with SOPS_AGE_KEY + R2 + gcloud ADC):
cd apps/platform-devices/cloudrun
# tofu init with R2 backend key cloud-deployment/apps/platform-devices/stawi-prod/terraform.tfstate
# tofu apply -var-file=envs/stawi-prod.tfvars -var=app_name=platform-devices ...
```

Deploy order: any order (no migrate cross-deps between platform apps). Identity stack must already be up for OIDC/authz URLs.

## Optional secrets (later)

| App | Secrets |
|-----|---------|
| devices | Cloudflare TURN (`CLOUDFLARE_TURN_*`) |
| files | R2/S3 (`S3_ENDPOINT`, `S3_ACCESS_KEY_*`, `ENCRYPTION_PHRASE`) |

## Container images

Cloud Run in this org rewrites GHCR pulls through `cache.europe-docker.pkg.dev` and fails without cache credentials.

**Bootstrap:** images are mirrored to:

```text
europe-west9-docker.pkg.dev/stawi-platform/apps/<name>:<tag>
```

Release ship workflows can keep pushing to GHCR; either mirror into AR in CI or configure GHCR remote repository auth. Prefer AR for production Cloud Run tags until GHCR pull is fixed org-wide.
