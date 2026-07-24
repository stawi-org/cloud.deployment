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

## Migrations (automatic on apply)

Each app root runs a **Cloud Run Job** (`{app}-migrate`) before the service:

| App | Migrate command | DB URL |
|-----|-----------------|--------|
| Frame services (auth, identity, profile, tenancy) | `migrate` | Neon **direct** (advisory locks) |
| Hydra | `migrate sql -e --yes` | Neon direct as `DSN` |
| Keto | `migrate up -y` | Neon direct as `DSN` |

Runtime services use the **pooled** Neon URL. Re-apply re-runs the job when the image or migrate args change.

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

## Container images (Artifact Registry)

GHCR pulls via org `cache.europe-docker.pkg.dev` often fail without cache credentials.
Bootstrap images live in project AR:

```text
europe-west9-docker.pkg.dev/stawi-identity/apps/<name>:<tag>
```

Mirror before first apply or when bootstrap tag changes:

```bash
./scripts/mirror-ghcr-to-ar.sh \
  --project stawi-identity --location europe-west9 --repo apps \
  --src ghcr.io/antinvestor/service-authentication:v1.54.53 \
  --name service-authentication --tag v1.54.53
```

Routine rolls still use decentralized **cloudrun-ship** (OpenTofu ignores image). Prefer shipping AR tags once the service repo is configured for dual push (GHCR + AR).

### Warm instances (usability)

| Service | `min_instance_count` | Why |
|---------|----------------------|-----|
| `identity-oauth2-hydra` | 1 | OIDC discovery used by every Frame cold start |
| `identity-authorization-keto-read` | 1 | ReBAC checks from Frame services |
| `identity-authentication` | 1 | Login/consent path |

## Still incomplete without extra work

| Item | Action |
|------|--------|
| Custom domains / DNS | Cloudflare / Cloud Run domain mapping |
| Ship Frame images to AR | Service-repo release → AR + `cloudrun-ship` (see [CLOUDRUN_SHIP.md](CLOUDRUN_SHIP.md)) |
| Tenancy service-bot → Keto bootstrap | Optional follow-up if migrate soft-fails |
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
