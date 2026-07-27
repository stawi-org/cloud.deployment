# Full identity deploy checklist (prod-first)

Greenfield identity on **Cloud Run + Neon + Pub/Sub + Secret Manager**, env **`stawi-prod`** → GCP project **`stawi-identity`**.

## What “fully deployed” requires

| Layer | Required | Status checklist |
|-------|----------|------------------|
| GCP project + WIF | `stawi-identity`, deploy SA, WIF for this repo | [ ] Bootstrap GCP prod done |
| Neon org + API key | Identity Neon org → SOPS file | [ ] Bootstrap Neon identity |
| GitHub repo secrets | R2 + age private key | [ ] `R2_*` + `SOPS_AGE_KEY` |
| Secret Manager runtime secrets | OpenTofu on apply | [ ] automatic |
| OpenTofu apply per app | 6 identity apps | [ ] plan/apply on `main` or workflow_dispatch |
| App config (Hydra/Keto URLs, etc.) | Beyond generic template | [ ] Follow-up if images need extra env |
| DNS / custom domains | accounts, oauth2, api | [ ] After smoke tests |

---

## Secrets: GitHub vs Secret Manager

See **[GITHUB_SECRETS.md](GITHUB_SECRETS.md)**.

**You only set four GitHub repository secrets:** R2 trio + `SOPS_AGE_KEY`.  
**Secret Manager is filled automatically on OpenTofu apply** (database URLs + generated crypto).

---

## Setup jobs (automatic on apply)

Each Frame app root runs a **Cloud Run Job** (`{app}-migrate` name; argv is **setup**):

| App | Job argv | DB URL |
|-----|----------|--------|
| Frame services (auth, identity, profile, tenancy) | `setup` (full plan: migrate + bootstrap + permissions + …) | Neon **direct** (advisory locks) |
| Hydra | `migrate sql -e --yes` | Neon direct as `DSN` |
| Keto | `migrate up -y` | Neon direct as `DSN` |

Frame jobs use `DO_SETUP=true` and `args = ["setup"]` so every registered setup step runs (schema, bootstrap, permission manifest registration). Do **not** use permissions-only or legacy `migrate` argv for normal deploys.

Runtime services use the **pooled** Neon URL. Re-apply re-runs the job when the image or setup args change.

## Deploy order (apply)

1. Confirm **R2** + **SOPS_AGE_KEY** on the repo.  
2. Confirm SOPS files exist:

```bash
ls credentials/gcp/identity/stawi-prod/auth.yaml
ls credentials/neon/identity/auth.yaml
```

3. Apply (workflow_dispatch `app-apply` or push) **one app at a time** first:

```
identity-oauth2-hydra
identity-authorization-keto
identity-authentication
identity-tenancy
identity-profile
identity-identity
```

4. Confirm each:

```bash
gcloud run services list --project=stawi-identity --region=europe-west9
gcloud secrets describe identity-authentication-database-url --project=stawi-identity
```

5. Smoke OIDC (login, token, JWKS) before DNS cutover.

---

## Public DNS / edge

**One hostname per service** (no Cloud Run path router). Full map: **[PUBLIC_EDGE_DNS.md](PUBLIC_EDGE_DNS.md)** + `config/public-edge.yaml`.

| Host | Service |
|------|---------|
| `accounts.stawi.org` | `identity-authentication` |
| `oauth2.stawi.org` | `identity-oauth2-hydra` |
| `api.stawi.org/profile` | `identity-profile` (path gateway) |
| `api.stawi.org/tenancy` | `identity-tenancy` (path gateway; IAM) |
| `api.stawi.org/identity` | `identity-identity` (path gateway) |

Product APIs under **`api.stawi.org/<path>`** → **`api-gateway`** (path LB in stawi-api).

Host front door: **`edge-lb-identity`** (accounts, oauth2, authz*, optional direct hosts — domain mapping unavailable in europe-west9).  
See **[PUBLIC_EDGE_DNS.md](PUBLIC_EDGE_DNS.md)**.

## Container images (public GHCR)

Service images are **public** on GHCR. Cloud Run pulls them directly — no
Artifact Registry mirror and no dual-push:

```text
ghcr.io/antinvestor/service-authentication:vX.Y.Z
ghcr.io/antinvestor/service-authentication-tenancy:vX.Y.Z
ghcr.io/antinvestor/service-profile:vX.Y.Z
ghcr.io/antinvestor/service-fintech-identity:vX.Y.Z
```

Bootstrap pins live in each app's `envs/stawi-prod.tfvars`. Routine rolls use
decentralized **cloudrun-ship** with the same `ghcr.io/...` tags.

See [CLOUDRUN_SHIP.md](CLOUDRUN_SHIP.md).

### Keep-warm (cheap, not min instances)

Frame apps fail hard if Hydra OIDC discovery is cold at process start. Instead of
paying ~$30/mo for `min_instance_count=1`, each critical service has a **Cloud
Scheduler** job that GETs a health/login path every **5 minutes**:

| Service | Scheduler job | Path |
|---------|---------------|------|
| `identity-oauth2-hydra` | `keep-warm-identity-oauth2-hydra` | `/health/ready` |
| `identity-authorization-keto-read` | `keep-warm-identity-authorization-keto-read` | `/health/ready` |
| `identity-authentication` | `keep-warm-identity-authentication` | `/s/login` |

Module: [`modules/cloudrun-keep-warm`](../modules/cloudrun-keep-warm).  
Cost is request/active seconds only (cents–few dollars/month at idle), not idle min-instance rates.  
Scheduler region: `europe-west1` (HTTP target still hits Cloud Run in `europe-west9`).

To pause keep-warm temporarily: set `paused = true` on the module or pause the job in GCP console.

## Still incomplete without extra work

| Item | Action |
|------|--------|
| Custom domains / DNS | Cloudflare / Cloud Run domain mapping |
| Ship Frame images to AR | Service-repo release → AR + `cloudrun-ship` (see [CLOUDRUN_SHIP.md](CLOUDRUN_SHIP.md)) |
| Tenancy service-bot → Keto bootstrap | Requires Frame TLS gRPC client + keto `use_http2` + migrate OAuth/Keto env (see FRAME_CLOUDRUN_APP.md) |
| Google OAuth client secrets | Optional `google_oauth_*` vars on authentication |

---

## Operator one-pager

```bash
# 0) Repo secrets already set: R2_* + SOPS_AGE_KEY

# 1) Local dry-run of credential load (needs private age key)
export SOPS_AGE_KEY='AGE-SECRET-KEY-...'
eval "$(./.github/scripts/load-sops-credentials.sh identity-authentication stawi-prod)"
echo "project=$TF_VAR_project_id region=$TF_VAR_region"

# 2) Trigger apply for one app
# GitHub Actions → app-apply → workflow_dispatch
#   app: identity-oauth2-hydra
#   env: stawi-prod
```
