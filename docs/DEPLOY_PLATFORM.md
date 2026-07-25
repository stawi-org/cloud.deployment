# Platform domain deploy (Cloud Run + Neon)

**GCP project:** `stawi-platform` (305282281906) · **region:** `europe-west9`  
**GCP account key:** `platform` (`config/gcp-accounts.yaml`)  
**Neon account key:** `platform` — **required for all platform apps going forward**  
**Neon org:** `org-calm-cell-68997035` (Stawi Platform)

Do **not** point platform apps at `neon.account: identity`. Identity Neon
(`org-rapid-mountain-41505493`) is reserved for `identity-*` apps
(`allowed_app_prefixes: [identity-]`). Platform Neon enforces
`allowed_app_prefixes: [platform-]`.

## Apps (live inventory)

| App | Image (AR bootstrap) | Neon project id | Source |
|-----|----------------------|-----------------|--------|
| `platform-devices` | `…/service-profile-devices:v1.53.5` | `rough-glade-86902865` | service-profile `apps/devices` |
| `platform-settings` | `…/service-profile-settings:v1.53.5` | `dark-base-48141714` | service-profile `apps/settings` |
| `platform-geolocation` | `…/service-profile-geolocation:v1.53.5` | `wispy-mouse-24359648` | service-profile `apps/geolocation` |
| `platform-files` | `…/service-files:v1.10.54` | `nameless-hat-40608441` | service-files |

App names must match Neon `allowed_app_prefixes: [platform-]`.

Cloud Run + migrate jobs: Ready in `stawi-platform` / `europe-west9`.  
DB secrets: `{app}-database-url` (+ `-direct`) in Secret Manager (Neon pooled/direct hosts, `eu-central-1`).  
Pub/Sub: regional `{app}-events` + push to `/_frame/queue/{app}-events`.

## Public DNS / edge

**One hostname per service** (Cloud Run domain mapping). No shared edge router.

| Host | Service |
|------|---------|
| `devices.stawi.org` | `platform-devices` |
| `settings.stawi.org` | `platform-settings` |
| `geolocation.stawi.org` | `platform-geolocation` |
| `files.stawi.org` | `platform-files` |

Front door: **`edge-lb-platform`** (Global HTTPS LB).  
Legacy `api.stawi.org/*` paths: optional **Cloudflare** routing.  
See **[PUBLIC_EDGE_DNS.md](PUBLIC_EDGE_DNS.md)**.

## Neon (required)

Every platform app uses **`neon.account: platform`** only — not identity.

| Artifact | Path / value |
|----------|--------------|
| Registry | `config/neon-accounts.yaml` → `accounts.platform` |
| SOPS API key | `credentials/neon/platform/auth.yaml` |
| Org id | **`org-calm-cell-68997035`** (registry `neon_org_id`; SOPS optional override) |
| Region | Neon `aws-eu-central-1` (see module defaults) |

CI (`load-sops-credentials.sh`) decrypts the platform key with `SOPS_AGE_KEY` and sets `TF_VAR_neon_api_key` / `TF_VAR_neon_org_id`.

### Org switch / rebind

If OpenTofu state still points at Neon projects created under the **identity** org (pre-switch), apply **rebinds** automatically: when `tofu refresh` of `module.db.neon_project` fails with the platform key, state drops `module.db.*` and creates fresh projects in the platform org.

**Orphan cleanup (manual):** projects left behind in the **identity** Neon org after rebind are not destroyed by OpenTofu. Delete them in the Neon console for **Stawi Identity** (`org-rapid-mountain-41505493`) once confirmed unused. Pre-switch orphans (all created when apps still had `neon.account: identity`):

| App | Orphan project (identity org) | Live project (platform org) |
|-----|-------------------------------|-----------------------------|
| `platform-devices` | `royal-dust-25392012` | `rough-glade-86902865` |
| `platform-settings` | `polished-paper-41931965` | `dark-base-48141714` |
| `platform-geolocation` | `dark-leaf-89149940` | `wispy-mouse-24359648` |
| `platform-files` | `summer-river-85045085` | `nameless-hat-40608441` |

Secret Manager on `stawi-platform` already points at the platform-org hosts; deleting the identity-org orphans is safe once you verify no other consumer uses them.

### Bootstrap / rotate platform Neon key

```bash
export API_KEY=napi_xxx   # org API key from Neon console (Stawi Platform)
./scripts/bootstrap-neon-account.sh --account platform --api-key "$API_KEY" \
  --org-hint "Stawi Platform" --org-id org-calm-cell-68997035 --force-repo-write
```

Always pass `--org-id org-calm-cell-68997035` so both registry and SOPS stay in sync.

## Dependencies on identity (GCP)

| Dependency | Where |
|------------|--------|
| Hydra OIDC | `stawi-identity` → `identity-oauth2-hydra` |
| Keto read/write | `stawi-identity` keto services |
| `hydra-webhook-psk` | Mirrored into `stawi-platform` Secret Manager |

`tofu-deploy@stawi-platform` has `roles/run.viewer` on `stawi-identity`.

## Ship (decentralized)

```
ship_service_account:       cloudrun-ship@stawi-platform.iam.gserviceaccount.com
workload_identity_provider: projects/305282281906/locations/global/workloadIdentityPools/github/providers/github-ship
```

| Repo | Ships |
|------|--------|
| service-profile | devices, settings, geolocation (+ identity-profile → stawi-identity) |
| service-files | platform-files |

## Apply

```bash
gh workflow run app-apply.yml -f app=platform-devices -f env=stawi-prod
# or apply all four after merging app.yaml / module changes
```

Order: independent; identity stack must already serve Hydra/Keto.

## Secrets

| App | Secrets |
|-----|---------|
| all | `DATABASE_URL`, `hydra-webhook-psk`, dual-URL `EVENTS_QUEUE_*` / `FRAME_QUEUE_PUSH_OIDC_*` |
| files | `ENCRYPTION_PHRASE` (32 bytes, generated) |
| devices | Cloudflare TURN (optional later) |
| files storage | R2/S3 endpoint + keys (optional later) |

## Container images

Org GHCR pulls via `cache.europe-docker.pkg.dev` often fail without cache credentials. Bootstrap images live in:

```text
europe-west9-docker.pkg.dev/stawi-platform/apps/<name>:<tag>
```

Mirror new release tags into AR before Cloud Run ship, or fix GHCR remote auth org-wide.
