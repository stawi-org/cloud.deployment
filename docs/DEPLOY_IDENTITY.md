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

## Still incomplete without extra work

| Item | Action |
|------|--------|
| Hydra/Keto **image config** (issuer URLs, login/consent, DSN env names) | Align container entrypoint/env with Ory |
| Frame services **service discovery** (public Cloud Run URLs for Hydra/Keto) | Set after first apply URIs are known |
| Custom domains / DNS | Cloudflare / Cloud Run domain mapping |
| Ship Frame images | Service-repo release → `cloudrun-ship` (see [CLOUDRUN_SHIP.md](CLOUDRUN_SHIP.md)); tfvars image is initial/bootstrap only |
| Migrations | Cloud Run Job or startup migrate for Frame services |

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
