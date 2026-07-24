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
  account: identity   # → config/gcp-accounts.yaml + credentials/gcp/identity/…
neon:
  account: identity   # → config/neon-accounts.yaml + credentials/neon/identity/…
```

**One Neon project per app** under the identity Neon org.

**Env policy (current):** apps list **`stawi-prod` only** → GCP project **`stawi-identity`**.  
`stawi-dev` stays a registry placeholder until a real dev project is bootstrapped; then add `stawi-dev` back under each app’s `envs:`.

## Account resolution

```bash
./.github/scripts/resolve-app-context.sh identity-authentication stawi-prod
export SOPS_AGE_KEY='AGE-SECRET-KEY-...'
eval "$(./.github/scripts/load-sops-credentials.sh identity-authentication stawi-prod)"
```

Returns / exports `project_id`, `region`, WIF, deploy SA, Neon API key. **Running an app is selecting accounts**, not hardcoding projects in Terraform.

## Secrets (nothing sensitive in git plaintext)

| Secret | Where | How used |
|--------|--------|----------|
| Neon **org** API key | SOPS `credentials/neon/identity/auth.yaml` | CI → `TF_VAR_neon_api_key` only |
| GCP WIF / deploy SA | SOPS `credentials/gcp/identity/stawi-prod/auth.yaml` | CI WIF auth |
| `DATABASE_URL` | Secret Manager `{app}-database-url` | Cloud Run `secret_key_ref` |
| Hydra system/cookie secrets, webhook PSKs | Secret Manager (OpenTofu `random_password`) | Cloud Run |
| R2 + age private key | GitHub repo secrets | CI backend + decrypt |

## Deploy order (build), single go-live

1. Bootstrap GCP **prod**: `--account identity --env stawi-prod --project stawi-identity`.  
2. Bootstrap Neon **identity** org (SOPS file on main).  
3. Set GitHub secrets: `R2_*` + `SOPS_AGE_KEY`.  
4. Apply apps against **`stawi-prod` only**.  
5. Order: Hydra → Keto → authentication → tenancy/profile/identity (or parallel then re-apply).  
6. Smoke OIDC; point DNS once.  
7. **Later:** bootstrap `stawi-dev` when capacity allows.

## Cost posture

Defaults are scale-to-zero Cloud Run + Neon autosuspend (see [BACKEND.md](BACKEND.md)). Six idle identity services should not run expensive always-on compute.

## Related docs

- [DEPLOY_IDENTITY.md](DEPLOY_IDENTITY.md)  
- [GITHUB_SECRETS.md](GITHUB_SECRETS.md)  
- [BACKEND.md](BACKEND.md)  
- [ADDING_AN_APP.md](ADDING_AN_APP.md)  
