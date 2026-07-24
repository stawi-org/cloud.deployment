# Identity domain — greenfield big-bang

Identity is re-implemented on **Cloud Run + Neon + Pub/Sub + Secret Manager**, not migrated live from the Talos `identity` namespace. Cutover is DNS + config once everything is healthy.

## Apps (all use the same accounts)

| Directory | Workload | Image placeholder |
|-----------|----------|-------------------|
| `apps/identity-authentication` | Auth service / accounts UI | `ghcr.io/antinvestor/service-authentication` |
| `apps/identity-oauth2-hydra` | Ory Hydra | `oryd/hydra` |
| `apps/identity-authorization-keto` | Ory Keto | `oryd/keto` |
| `apps/identity-tenancy` | Tenancy API | `ghcr.io/antinvestor/service-tenancy` |
| `apps/identity-profile` | Profile API | `ghcr.io/antinvestor/service-profile` |
| `apps/identity-identity` | Identity API | `ghcr.io/antinvestor/service-identity` |

Every app.yaml:

```yaml
gcp:
  account: identity   # → config/gcp-accounts.yaml
neon:
  account: identity   # → config/neon-accounts.yaml
```

**One Neon project per app** under the identity Neon org. **One GCP project per env** (`stawi-identity-dev` / `stawi-identity-prod` placeholders).

## Account resolution

```bash
./.github/scripts/resolve-app-context.sh identity-authentication stawi-dev
```

Returns `project_id`, `region`, WIF provider, deploy SA, Neon SM secret location, etc. CI uses this so **running an app is selecting accounts**, not hardcoding projects in Terraform.

## Secrets (nothing sensitive in git)

| Secret | Where | How used |
|--------|--------|----------|
| Neon **org** API key | Secret Manager `neon-org-api-key` in identity GCP project (preferred) | CI → `TF_VAR_neon_api_key` only |
| `DATABASE_URL` | Secret Manager `{app}-database-url` | Cloud Run `secret_key_ref` |
| Hydra system/cookie secrets, webhook PSKs, Google OAuth | Secret Manager (`extra_secret_ids` or out-of-band versions) | Cloud Run |
| R2 state keys | GitHub repo secrets | CI tofu backend |

Bootstrap Neon org key once per env:

```bash
# After WIF / gcloud auth as admin
echo -n "$NEON_ORG_API_KEY" | gcloud secrets create neon-org-api-key \
  --project=stawi-identity-dev \
  --data-file=-
# grant tofu-deploy@… secretAccessor on that secret
```

## Deploy order (build), single go-live

1. Fill real `project_id` / WIF in `config/gcp-accounts.yaml` for `identity`.  
2. Create GCP projects, enable APIs (Run, SM, Pub/Sub, IAM), WIF, deploy SA.  
3. Store `neon-org-api-key` in SM.  
4. Apply in order: Hydra → Keto → authentication → tenancy/profile/identity (or all in parallel if images tolerate empty deps, then re-apply).  
5. Smoke OIDC (login, token, userinfo, Keto check).  
6. Point DNS (`accounts`, `oauth2`, API paths) once.  

## Ory (Hydra / Keto) notes

Templates are the **same Cloud Run root shape**. Before production:

- Replace image tags with pinned digests.  
- Add Hydra/Keto-specific env and SM secrets (system secret, DSN already via DATABASE_URL pattern — may need Ory DSN env name mapping in a follow-up).  
- Protect Hydra admin (IAM / ingress).  
- Wire public URLs for issuer, login, consent, JWKS.

## Related docs

- [Multi-account platform design](superpowers/specs/2026-07-24-multi-account-platform-identity-greenfield.md)  
- [Neon multi-account secrets](superpowers/specs/2026-07-24-neon-multi-account-secrets-design.md)  
- [BACKEND.md](BACKEND.md)  
- [ADDING_AN_APP.md](ADDING_AN_APP.md)  
