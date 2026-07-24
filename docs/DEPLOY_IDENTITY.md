# Full identity deploy checklist (prod-first)

Greenfield identity on **Cloud Run + Neon + Pub/Sub + Secret Manager**, env **`stawi-prod`** → GCP project **`stawi-identity`**.

## What “fully deployed” requires

| Layer | Required | Status checklist |
|-------|----------|------------------|
| GCP project + WIF | `stawi-identity`, deploy SA, WIF for this repo | [ ] Bootstrap GCP prod done |
| Neon org + API key | Identity Neon org | [ ] Bootstrap Neon + GH env and/or SM |
| GitHub repo secrets | R2 state backend | [ ] `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` |
| GitHub environments | Optional protection | [ ] `gcp-identity-prod`, `neon-identity` exist |
| Secret Manager runtime secrets | Seeded (see below) | [ ] `seed-gcp-secrets.sh` |
| OpenTofu apply per app | 6 identity apps | [ ] plan/apply on `main` or workflow_dispatch |
| App config (Hydra/Keto URLs, etc.) | Beyond generic template | [ ] Follow-up if images need extra env |
| DNS / custom domains | accounts, oauth2, api | [ ] After smoke tests |

---

## Critical CI detail (Neon key)

Job `environment` is usually **`gcp-identity-prod`**.  
Secrets on **`neon-identity`** are **not** injected into that job.

Therefore **`neon-org-api-key` must exist in Secret Manager** on `stawi-identity` for CI OpenTofu to create Neon projects.

```bash
# Preferred after you can decrypt SOPS (private age key) OR from env:
export NEON_ORG_API_KEY='napi_...'   # or from sops -d

./scripts/seed-gcp-secrets.sh \
  --project stawi-identity \
  --env stawi-prod \
  --app identity-authentication \
  --set "neon-org-api-key=${NEON_ORG_API_KEY}"

# Or from SOPS (needs private age key):
./scripts/seed-gcp-secrets.sh \
  --app identity-authentication \
  --env stawi-prod \
  --from-sops-neon identity
```

---

## Secrets → Secret Manager

Catalog: [`config/secret-catalog/identity.yaml`](../config/secret-catalog/identity.yaml)  
Seeder: [`scripts/seed-gcp-secrets.sh`](../scripts/seed-gcp-secrets.sh)  
Example env file: [`scripts/generate-identity-secrets.env.example`](../scripts/generate-identity-secrets.env.example)

### 1. Create a local env file (never commit)

```bash
cp scripts/generate-identity-secrets.env.example secrets.identity.local.env
chmod 600 secrets.identity.local.env
# edit: paste Google OAuth, generate randoms, Neon key, etc.
```

### 2. Generate random crypto material where empty

```bash
gcloud config set project stawi-identity   # or ADC for that project

./scripts/seed-gcp-secrets.sh \
  --app identity-authentication \
  --env stawi-prod \
  --from-env-file ./secrets.identity.local.env \
  --generate-missing

./scripts/seed-gcp-secrets.sh \
  --app identity-oauth2-hydra \
  --env stawi-prod \
  --from-env-file ./secrets.identity.local.env \
  --generate-missing
```

`--generate-missing` fills empty catalog keys with `openssl rand` (except database URLs).

### 3. Verify

```bash
gcloud secrets list --project=stawi-identity
gcloud secrets versions access latest --secret=neon-org-api-key --project=stawi-identity | wc -c
```

### Secret inventory

| Secret ID | Used by | Notes |
|-----------|---------|--------|
| `neon-org-api-key` | CI only | Neon org API key |
| `hydra-webhook-psk` | auth + hydra | Shared webhook bearer |
| `identity-authentication-google-oauth-client-id` | auth | Google OAuth |
| `identity-authentication-google-oauth-client-secret` | auth | Google OAuth |
| `identity-authentication-csrf-secret` | auth | Session/CSRF |
| `identity-authentication-cookie-hash-key` | auth | Cookie |
| `identity-authentication-cookie-block-key` | auth | Cookie |
| `identity-oauth2-hydra-secrets-system` | hydra | Ory system secret |
| `identity-oauth2-hydra-secrets-cookie` | hydra | Ory cookie secret |
| `{app}-database-url` | each app | **Created by OpenTofu** from Neon |

Runtime SA gets `secretAccessor` via `modules/app-secrets` on apply.

---

## Deploy order (apply)

1. **Seed secrets** (above), especially `neon-org-api-key`.  
2. Confirm **R2** repo secrets for tofu state.  
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

## GitHub secrets you must set (repo-level)

| Name | Purpose |
|------|---------|
| `R2_ACCOUNT_ID` | Tofu state |
| `R2_ACCESS_KEY_ID` | Tofu state |
| `R2_SECRET_ACCESS_KEY` | Tofu state |

Optional: repository-level `NEON_API_KEY` if you refuse SM for Neon (not preferred when job env is `gcp-identity-prod`).

WIF uses **public** provider + SA from `config/gcp-accounts.yaml` (no GH secret for WIF).

---

## Still incomplete without extra work

These are **not** fully solved by the generic Cloud Run template alone:

| Item | Action |
|------|--------|
| Hydra/Keto **image config** (issuer URLs, login/consent, DSN env names) | Align container entrypoint/env with Ory; may need custom `main.tf` env beyond secrets |
| Frame services **service discovery** (public Cloud Run URLs for Hydra/Keto) | Set after first apply URIs are known (second apply or tfvars) |
| Custom domains / DNS | Cloudflare / Cloud Run domain mapping |
| Pin image digests | Replace `:latest` in `envs/stawi-prod.tfvars` |
| Migrations | Cloud Run Job or startup migrate for Frame services |

---

## Operator one-pager

```bash
# 0) Auth as someone who can write SM on stawi-identity
gcloud auth login
gcloud config set project stawi-identity

# 1) Seed secrets (including neon-org-api-key)
cp scripts/generate-identity-secrets.env.example secrets.identity.local.env
# fill neon-org-api-key + Google OAuth; leave crypto blank to auto-generate
./scripts/seed-gcp-secrets.sh --app identity-authentication --env stawi-prod \
  --from-env-file ./secrets.identity.local.env --generate-missing
./scripts/seed-gcp-secrets.sh --app identity-oauth2-hydra --env stawi-prod \
  --from-env-file ./secrets.identity.local.env --generate-missing

# 2) Repo: ensure R2 secrets exist on GitHub

# 3) Trigger plan/apply for identity apps (stawi-prod)

# 4) Wire public URLs + DNS after smoke
```

## Related

- [IDENTITY_GREENFIELD.md](IDENTITY_GREENFIELD.md)  
- [BACKEND.md](BACKEND.md)  
- [GCP_BOOTSTRAP.md](GCP_BOOTSTRAP.md) / [NEON_BOOTSTRAP.md](NEON_BOOTSTRAP.md)  
