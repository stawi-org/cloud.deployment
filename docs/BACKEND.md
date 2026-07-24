# Backend: accounts, state, and secrets

## Principle

**Git holds registries + SOPS-encrypted account credentials.**  
**Secret Manager holds runtime secrets.**  
**Selecting GCP + Neon accounts in `app.yaml` is how you choose where an app runs.**

```
app.yaml
  gcp.account  → config/gcp-accounts.yaml  → project_id, region, WIF, deploy SA
                 credentials/gcp/<account>/<env>/auth.yaml  (SOPS — CI source of truth)
  neon.account → config/neon-accounts.yaml → policy / org hint
                 credentials/neon/<account>/auth.yaml       (SOPS — org API key)
```

Resolve anytime:

```bash
./.github/scripts/resolve-app-context.sh <app> <env>
eval "$(./.github/scripts/load-sops-credentials.sh <app> <env>)"  # needs SOPS_AGE_KEY
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
- `workload_identity_provider`, `deploy_service_account` (public mirror; also in SOPS)
- `sops_auth_path`, `labels`

### What lives in which GCP project

For a given app env, **one project** hosts:

- Cloud Run services  
- Pub/Sub  
- Secret Manager (runtime secrets)  
- Runtime service accounts  

---

## Multi-Neon accounts

Registry: [`config/neon-accounts.yaml`](../config/neon-accounts.yaml)

Domain orgs: `identity`, `notifications`, `payments`, `platform`, `labs`.

| Account | Org id (when set) | App name prefixes |
|---------|-------------------|-------------------|
| `identity` | `org-rapid-mountain-41505493` | `identity-` |
| `platform` | `org-calm-cell-68997035` | `platform-` |
| `payments` | (set on bootstrap) | `payment-`, `checkout-`, `billing-`, `ledger-` |
| `notifications` | (set on bootstrap) | (open until set) |
| `labs` | (set on bootstrap) | (open; dev only) |

**One Neon project per app** (OpenTofu module). Org API key is **deploy-time only**, from SOPS.

CI: `SOPS_AGE_KEY` → decrypt `credentials/neon/<account>/auth.yaml` → `TF_VAR_neon_api_key` + `TF_VAR_neon_org_id`.

Going forward, **never** create platform domain databases in the identity Neon org. See [DEPLOY_PLATFORM.md](DEPLOY_PLATFORM.md).

---

## Secret Manager inventory (runtime)

| Secret ID pattern | Contents | Consumer |
|-------------------|----------|----------|
| `{app}-database-url` | Neon pooled connection URI | Cloud Run `DATABASE_URL` |
| App-specific (Hydra system secret, OAuth client, webhook PSK, …) | Sensitive config | Cloud Run via `secret_env` |

Module: [`modules/app-secrets`](../modules/app-secrets).

### What must never be in git (plaintext)

- Database passwords / connection strings  
- Neon org API keys (only SOPS-encrypted)  
- OAuth client secrets, Hydra system secrets, session secrets  
- R2 access keys / `SOPS_AGE_KEY`  
- Any private key material  

---

## R2 OpenTofu state

| Item | Value |
|------|--------|
| Bucket | `cloud-tofu-state` |
| Key | `cloud-deployment/apps/<app>/<env>/terraform.tfstate` |
| Lock | `use_lockfile = true` |
| Creds | GitHub secrets `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` |

Fragment: [`config/r2-backend.hcl`](../config/r2-backend.hcl).

---

## CI flow (per app job)

1. Detect changed apps (path + module impact).  
2. Enrich matrix via `resolve-app-context` (GCP + optional Neon paths).  
3. Decrypt SOPS credentials (`SOPS_AGE_KEY`).  
4. WIF → deploy SA for `project_id`.  
5. `tofu init` (R2 `cloud-tofu-state`) → plan/apply.  

Independent concurrency: `cloud-deploy-<app>-<env>`.

**No GitHub Environments** for credentials (`neon--*`, `deploy--*` removed).

---

## Cost defaults (robust, not expensive)

| Layer | Default | Why |
|-------|---------|-----|
| Cloud Run `min_instance_count` | `0` | Scale to zero |
| Cloud Run `max_instance_count` | `5` | Cap burst cost |
| Cloud Run `cpu_idle` | `true` | CPU only during requests |
| Neon min/max CU | `0.25` / `1` | Cheap floor + modest ceiling |
| Neon suspend | `300s` | Idle compute off |
| Neon history | `86400s` (1 day) | Enough PITR without long retention bills |

Override per app in module inputs when needed.

---

## Bootstrap checklist (new GCP account)

1. Create GCP project(s) for the env.  
2. Run `scripts/bootstrap-gcp-account.sh` (WIF + SA + SOPS + registry).  
3. Ensure repo secrets: R2 + `SOPS_AGE_KEY`.  
4. Run `./.github/scripts/resolve-app-context.sh <app> stawi-prod`.

## Bootstrap checklist (new Neon org)

1. Create org + API key in Neon console.  
2. Run `scripts/bootstrap-neon-account.sh --account <key> --api-key …`.  
3. Merge the SOPS PR. CI picks up the key automatically.

## Identity greenfield

See [IDENTITY_GREENFIELD.md](IDENTITY_GREENFIELD.md) and [DEPLOY_IDENTITY.md](DEPLOY_IDENTITY.md).
