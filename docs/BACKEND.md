# Backend: accounts, state, and secrets

## Principle

**Git holds registries only (non-secret).**  
**Secret Manager holds runtime secrets and preferred deploy-time Neon org keys.**  
**Selecting GCP + Neon accounts in `app.yaml` is how you choose where an app runs.**

```
app.yaml
  gcp.account  → config/gcp-accounts.yaml  → project_id, region, WIF, deploy SA
  neon.account → config/neon-accounts.yaml → Neon org + SM secret for API key
```

Resolve anytime:

```bash
./.github/scripts/resolve-app-context.sh <app> <env>
# or --format=exports
```

---

## Multi-GCP accounts

Registry: [`config/gcp-accounts.yaml`](../config/gcp-accounts.yaml)

| Account key | Purpose |
|-------------|---------|
| `identity` | Auth, Hydra, Keto, profile, tenancy, identity |
| `notifications` | Notification workers |
| `payments` | Checkout / billing edges |
| `platform` | Shared platform edges |
| `labs` | Experiments (dev only) |

Each key has **per-env** slices (`stawi-dev`, `stawi-prod`) with:

- `project_id`, `region`
- `workload_identity_provider`, `deploy_service_account` (not secrets)
- `github_environment` (optional apply protection)
- `labels`

Replace placeholder project IDs and WIF resource names before apply.

### What lives in which GCP project

For a given app env, **one project** hosts:

- Cloud Run services  
- Pub/Sub  
- Secret Manager (runtime secrets + optionally Neon org API key)  
- Runtime service accounts  

---

## Multi-Neon accounts

Registry: [`config/neon-accounts.yaml`](../config/neon-accounts.yaml)

Domain orgs: `identity`, `notifications`, `payments`, `platform`, `labs`.

**One Neon project per app** (OpenTofu module). Org API key is **deploy-time only**.

### Neon API key storage (preferred: Secret Manager)

```yaml
# in neon-accounts.yaml
secret_manager:
  gcp_account: identity      # which GCP account registry key
  secret_id: neon-org-api-key
```

CI: WIF into the app’s GCP project →  
`gcloud secrets versions access latest --secret=neon-org-api-key --project=<resolved>` →  
`TF_VAR_neon_api_key`.

Fallback: GitHub Environment `neon-*` secret `NEON_API_KEY`.

---

## Secret Manager inventory (runtime)

| Secret ID pattern | Contents | Consumer |
|-------------------|----------|----------|
| `{app}-database-url` | Neon pooled connection URI | Cloud Run `DATABASE_URL` |
| App-specific (Hydra system secret, OAuth client, webhook PSK, …) | Sensitive config | Cloud Run via `secret_env` / `extra_secret_ids` |
| `neon-org-api-key` | Neon org API key | **CI only**, not Cloud Run |

Module: [`modules/app-secrets`](../modules/app-secrets) creates secrets, versions (when values passed from tofu), and `secretAccessor` for the runtime SA.

Cloud Run mounts secrets with `value_source.secret_key_ref` (see `modules/cloudrun-service`) — **not** plain env values from git.

### What must never be in git

- Database passwords / connection strings  
- Neon org API keys  
- OAuth client secrets, Hydra system secrets, session secrets  
- R2 access keys  
- Any private key material  

---

## R2 OpenTofu state

| Item | Value |
|------|--------|
| Bucket | `cluster-tofu-state` (shared name with infra; prefix isolation) |
| Key | `cloud-deployment/apps/<app>/<env>/terraform.tfstate` |
| Lock | `use_lockfile = true` |
| Creds | GitHub secrets `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` |

Fragment: [`config/r2-backend.hcl`](../config/r2-backend.hcl).

---

## CI flow (per app job)

1. Detect changed apps (path + module impact).  
2. Enrich matrix via `resolve-app-context` (GCP + Neon).  
3. Optional GitHub Environment = GCP account env for protection.  
4. WIF → deploy SA for `project_id`.  
5. Fetch Neon org key from Secret Manager (fallback GH).  
6. `tofu init` (R2) → plan/apply with `-var project_id=… -var region=…`.  

Independent concurrency: `cloud-deploy-<app>-<env>`.

---

## Bootstrap checklist (new GCP account)

1. Create GCP project(s) for dev/prod.  
2. Enable APIs: `run`, `secretmanager`, `pubsub`, `iam`, `iamcredentials`, `sts`.  
3. Create deploy SA + WIF pool/provider for GitHub `stawi-org/cloud.deployment`.  
4. IAM: deploy SA can admin Run, SM, Pub/Sub, service accounts in project.  
5. Create SM secret `neon-org-api-key` with Neon org API key; grant deploy SA `secretAccessor`.  
6. Update `config/gcp-accounts.yaml` with real `project_id` and WIF names.  
7. Run `./.github/scripts/resolve-app-context.sh <app> stawi-dev` and a plan.

---

## Identity greenfield

See [IDENTITY_GREENFIELD.md](IDENTITY_GREENFIELD.md) for the six identity apps and big-bang go-live order.

## Related specs

- [Multi-account platform + identity](superpowers/specs/2026-07-24-multi-account-platform-identity-greenfield.md)  
- [Neon multi-account secrets](superpowers/specs/2026-07-24-neon-multi-account-secrets-design.md)  
