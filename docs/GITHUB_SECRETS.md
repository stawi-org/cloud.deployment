# GitHub secrets (manual) vs Secret Manager (automatic)

## Principle

| Store | What you set by hand | What is automatic |
|-------|----------------------|-------------------|
| **GitHub** | Only CI credentials that OpenTofu needs **before/during** apply | — |
| **GCP Secret Manager** | **Nothing required by hand** for normal deploys | OpenTofu creates/writes runtime secrets on apply |

You do **not** manually copy database URLs or generated app secrets into Secret Manager.

---

## 1. GitHub — repository secrets (required)

Settings → Secrets and variables → Actions → **Repository secrets**:

| Secret name | Purpose |
|-------------|---------|
| `R2_ACCOUNT_ID` | Cloudflare R2 account id for OpenTofu state |
| `R2_ACCESS_KEY_ID` | R2 access key |
| `R2_SECRET_ACCESS_KEY` | R2 secret key |
| `NEON_API_KEY` | Neon **org** API key used by OpenTofu to create/manage Neon projects |

### Why `NEON_API_KEY` is a **repository** secret

CI jobs use the GitHub Environment `gcp-identity-prod` for deploy protection.  
Secrets attached only to `neon-identity` are **not** visible in that job.

So the Neon org key must be either:

- a **repository** secret named `NEON_API_KEY`, or  
- Secret Manager `neon-org-api-key` (optional cache; **not required** if the repo secret is set)

`bootstrap-neon-account.sh --sync-github-env` sets the **environment** secret. For CI, also set the **same value** as a **repository** secret `NEON_API_KEY` (UI or `gh secret set NEON_API_KEY`).

---

## 2. GitHub — environment secrets (optional)

| Environment | Secrets to set | Required? |
|-------------|----------------|-----------|
| `neon-identity` | `NEON_API_KEY` | Optional (duplicate of repo secret; useful if bootstrap created it) |
| `neon-payments` | `NEON_API_KEY` | Only when that domain is used (prefer repo secret naming later if multi-key) |
| `gcp-identity-prod` | *(none)* | Optional env for branch protection only |
| `gcp-identity-dev` | *(none)* | Deferred |

No Google OAuth, Hydra system secrets, or DB passwords belong in GitHub.

---

## 3. Secret Manager — automatic (OpenTofu)

On each successful **apply**, OpenTofu (via `modules/app-secrets` + Neon module):

| Secret | Source |
|--------|--------|
| `{app}-database-url` | Neon pooled connection URI (created by tofu) |
| Generated crypto (csrf, cookie keys, Hydra system/cookie, webhook PSK, …) | `random_password` resources written to SM on apply |
| IAM for runtime SA | tofu grants `secretAccessor` |

### Human-only values (still not GitHub env secrets)

If the app needs **Google OAuth client id/secret**, pass them **once** as OpenTofu variables in CI (or a one-shot `TF_VAR_…` / optional sensitive var file that is **not** committed). Prefer:

```bash
# optional one-time or CI vars — written into SM by tofu, not stored in git
TF_VAR_google_oauth_client_id=...
TF_VAR_google_oauth_client_secret=...
```

If unset, tofu can leave placeholder secrets empty until set — or you omit Google login until configured.

**Do not** use `seed-gcp-secrets.sh` for day-to-day deploys. That script is only an emergency/import tool.

---

## 4. Minimal setup checklist

1. [ ] Repo secrets: `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`  
2. [ ] Repo secret: `NEON_API_KEY` (identity Neon org key)  
3. [ ] (Optional) Environments for protection: `gcp-identity-prod`  
4. [ ] Apply apps — Secret Manager filled automatically  

---

## 5. Multi-domain later

When you have multiple Neon orgs, either:

- one repo secret per domain (`NEON_API_KEY_IDENTITY`, `NEON_API_KEY_PAYMENTS`) and CI maps `neon.account` → name, or  
- keep a single `NEON_API_KEY` only while identity is the only domain  

GCP WIF provider / deploy SA stay in **`config/gcp-accounts.yaml`** (not secrets).
