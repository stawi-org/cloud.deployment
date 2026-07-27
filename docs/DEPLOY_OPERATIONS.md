# Deploy operations domain (Cloud Run + Neon)

Operations services from `deployment.manifests/namespaces/operations`, deployed to:

| Plane | Account key | Project / org |
|-------|-------------|----------------|
| GCP | `operations` | `stawi-operations` (europe-west9) |
| Neon | `operations` | org registered via `bootstrap-neon-account.sh` |

## Applications

| App directory | K8s name | Image (GHCR) | DB | Extensions |
|---------------|----------|--------------|----|------------|
| `operations-audit` | service-audit | `service-authentication-audit` | yes | base + **timescaledb** |
| `operations-formstore` | operations-formstore | `service-trustage-formstore` | yes | base |
| `operations-queuestore` | operations-queuestore | `service-trustage-queue` | yes | base |
| `operations-redirect` | service-redirect | `service-files-redirect` | yes | base |
| `operations-trustage` | trustage | `service-trustage` | yes | base + **timescaledb** |
| `operations-thesa` | service-thesa | `service-thesa` | **no** | — |

**Base extensions:** `uuid-ossp`, `pg_stat_statements`, `pg_trgm`, `btree_gin`, `btree_gist`  
(as in CNPG Database CRs under `deployment.manifests/namespaces/operations/*/database.yaml`).

**Not used on new Neon projects:** `pg_search` (deprecated for new Neon projects as of 2026-03).  
**postgis:** enable per-app via `neon_extensions` in tfvars when a service needs geo (none of the current operations apps declare postgis in K8s).

## Prerequisites

0. **Cross-project IAM (once):** ops deploy SA must read identity Cloud Run (Hydra/Keto URIs):
   ```bash
   gcloud projects add-iam-policy-binding stawi-identity \
     --member="serviceAccount:tofu-deploy@stawi-operations.iam.gserviceaccount.com" \
     --role="roles/run.viewer"
   ```
   (Platform uses the same pattern for `tofu-deploy@stawi-platform`.)

1. GCP account bootstrapped:
   ```bash
   ./scripts/bootstrap-gcp-account.sh \
     --project stawi-operations \
     --account operations \
     --env stawi-prod \
     --region europe-west9
   ```
2. Neon account bootstrapped (API key + SOPS):
   ```bash
   ./scripts/bootstrap-neon-account.sh \
     --account operations \
     --api-key "$API_KEY" \
     --org-hint "Stawi Operations" \
     --org-id org-xxxx   # optional but recommended
   ```
3. Repo secrets: `SOPS_AGE_KEY`, `R2_*`, and (if edge hosts later) `CLOUDFLARE_API_TOKEN`.
4. **Shared secrets** in project `stawi-operations` (OpenTofu-managed on first apply):
   - `hydra-webhook-psk` — owned by **operations-audit**. Value is **copied from
     stawi-identity** via data source (must match so private_key_jwt webhooks to
     `accounts.stawi.org` succeed). One-time IAM:
     ```bash
     gcloud secrets add-iam-policy-binding hydra-webhook-psk --project=stawi-identity \
       --member="serviceAccount:tofu-deploy@stawi-operations.iam.gserviceaccount.com" \
       --role="roles/secretmanager.secretAccessor"
     ```
   - `audit-signing-key` — owned by **operations-audit** (hex, 64 bytes after decode)
   - `service-files-encryption` — owned by **operations-redirect**

   Apply **operations-audit** (and **operations-redirect** if needed) before other ops apps so
   shared secret IAM bindings succeed.
5. **Images:** public GHCR — pin `ghcr.io/antinvestor/…:vX.Y.Z` in each app's
   `envs/stawi-prod.tfvars`. No Artifact Registry mirror required. See
   [CLOUDRUN_SHIP.md](CLOUDRUN_SHIP.md).

## Extensions (OpenTofu)

`modules/neon-database` accepts `extensions` and runs `CREATE EXTENSION IF NOT EXISTS … CASCADE` via `psql` after the Neon project/DB exist. CI install step provides `postgresql-client` when needed.

Override per app in `apps/<app>/cloudrun/envs/stawi-prod.tfvars`:

```hcl
neon_extensions = ["uuid-ossp", "pg_trgm", "timescaledb"]
```

## Apply (CI)

```bash
for app in operations-audit operations-formstore operations-queuestore \
           operations-redirect operations-trustage operations-thesa; do
  gh workflow run app-apply.yml -f app="$app" -f env=stawi-prod
done
```

## Runtime verification (stawi-prod)

```bash
# CI: Ready + secret mounts + /readyz (also grants operator viewer IAM)
gh workflow run ops-verify.yml -f project=stawi-operations -f region=europe-west9
```

All six Cloud Run services on **stawi-operations** report **Ready** and **`/readyz` HTTP 200**
(authenticated ID-token probe). Verified 2026-07-27:

| Service | Ready | `/readyz` | Neon / secrets |
|---------|-------|-----------|----------------|
| operations-audit | yes | 200 | base + timescaledb; `AUDIT_SIGNING_KEY`, `DATABASE_URL` |
| operations-formstore | yes | 200 | base; `DATABASE_URL` |
| operations-queuestore | yes | 200 | base; `DATABASE_URL` |
| operations-redirect | yes | 200 | base; `ENCRYPTION_PHRASE`, analytics username/password |
| operations-thesa | yes | 200 | no DB; analytics backend URL/token |
| operations-trustage | yes | 200 | base + timescaledb; multi-topic Pub/Sub |

Trustage multi-topic env (applied): `QUEUE_EXEC_*` → `operations-trustage-exec`,
`QUEUE_EVENT_*` → `operations-trustage-wf-events`, Frame events dual-URL + OIDC push,
`CACHE_REQUIRE_VALKEY=false`, `MinInstancesProvisioned`.

## Notes / gaps vs K8s

- **Messaging:** Cloud Run uses **Pub/Sub** (Frame dual URL), not in-cluster NATS.
  - Most apps: single `{app}-events` topic + push subscription (Frame events).
  - **operations-trustage:** multi-topic Pub/Sub — `events`, `exec`, `wf-events` with push
    workers (`exec-worker`, `event-router`). Scheduler wake queues remain in-process
    (`mem://`); trustage runs with `min_instance_count = 1`.
- **Valkey / Redis:** K8s `VALKEY_CACHE_URL` is not provisioned; trustage sets
  `CACHE_REQUIRE_VALKEY=false`. Add Memorystore when cache is required.
- **Public hosts / edge:** no `edge-lb-operations` yet; path routes on `api.stawi.org`
  (Cloudflare / future LB) still to wire for production public paths.
- **Migrate jobs:** created with `execute = false`; run manually or flip when schema
  changes need applying.
- **thesa** has no Neon DB; analytics secrets are optional at runtime.
- **Logging / project IAM:** `tofu-deploy@stawi-operations` needs `roles/logging.viewer`
  (listed in bootstrap). If debug workflows cannot read logs, a **project owner** must
  re-run `./scripts/bootstrap-gcp-account.sh … --iam-only` or grant:
  ```bash
  gcloud projects add-iam-policy-binding stawi-operations \
    --member='serviceAccount:tofu-deploy@stawi-operations.iam.gserviceaccount.com' \
    --role='roles/logging.viewer'
  ```
  Human identities currently have no direct access to `stawi-operations` (CI WIF only).
