# Deploy opportunities (Cloud Run product + cluster crawl)

Customer-facing **discovery** and **matching** move to Cloud Run + Neon.  
**Crawl / ingest** remains on the Kubernetes cluster (CNPG + NATS).

| Plane | Account key | Project / org |
|-------|-------------|----------------|
| GCP | `opportunities` | `stawi-opportunities` (europe-west1) |
| Neon | `opportunities` | org via `bootstrap-neon-account.sh` (SOPS present) |

**Spec:** [superpowers/specs/2026-07-29-opportunities-cloudrun-neon-design.md](superpowers/specs/2026-07-29-opportunities-cloudrun-neon-design.md)

## Applications (Cloud Run)

| App directory | Role | Neon | Public path |
|---------------|------|------|-------------|
| `opportunities-matching` | Candidates, matches, CV/chat, billing webhooks; **owns product Neon** | yes (owner) | `/matching` |
| `opportunities-api` | Public search + detail; **no second Neon project** | attaches matching URL | **`/opportunities`** |

**Not Cloud Run:** crawler, frontier-worker, worker-*, writer, materializer, NATS.

## Data split (cost)

| Neon product (high value) | CNPG crawl (cluster) |
|---------------------------|----------------------|
| opportunities catalog, companies, flags | sources, recipes, crawl_runs |
| candidates, matches, placement, saved jobs | url_frontier, host_state |
| billing entitlement cache / checkouts | job_ingest_queue, ingest events |

Search on Neon uses **`lakebase_text`** (BM25), **not** `pg_search`.

## Path migration

| Old | New (canonical) |
|-----|-----------------|
| `/jobs` | **`/opportunities`** |
| OAuth resource `/jobs` | **`/opportunities`** |
| `/matching` | `/matching` (unchanged) |

Temporary 308 `/jobs` → `/opportunities` may be used during SPA cutover; remove after greenfield soak.

## Prerequisites

1. GCP + Neon onboard for `opportunities` (merged).
2. **Lakebase Search** enabled on the Neon product project (console/API) so `CREATE EXTENSION lakebase_text` succeeds.
3. Cross-project: deploy SA can read identity Hydra/Keto if required by module.
4. Seed SM in `stawi-opportunities`:
   - `hydra-webhook-psk` (copy from identity)
   - `billing-webhook-secret`
   - `checkout-internal-token` (must match checkout)
5. Images: `ghcr.io/stawi-opportunities/opportunities-{api,matching}:vX.Y.Z` (public GHCR).

## Apply order

```text
1. identity (Hydra/Keto) already live
2. opportunities-matching   # Neon + migrations + Pub/Sub + secrets shells
3. opportunities-api        # shared DB IAM + edge
4. Enable edge routes in routes.prod.json (origin after apply)
5. Cluster worker: CRAWL_DATABASE_URL + PRODUCT_DATABASE_URL + MATCHING_FANOUT_QUEUE_URL=gcppubsub://stawi-opportunities/opportunities-fanout
6. Smoke gates → remove cluster HTTPRoutes /jobs + /matching → scale cluster api/matching to 0
```

```bash
gh workflow run app-apply.yml -f app=opportunities-matching -f env=stawi-prod
# wait for Ready + migrate
gh workflow run app-apply.yml -f app=opportunities-api -f env=stawi-prod
```

## Reused services (do not reimplement)

| Env | URL |
|-----|-----|
| `PROFILE_SERVICE_URI` | `https://api.stawi.org/profile` |
| `FILE_SERVICE_URI` | `https://api.stawi.org/files` |
| `REDIRECT_SERVICE_URI` | `https://api.stawi.org/redirect` |
| `NOTIFICATION_SERVICE_URI` | `https://api.stawi.org/notification` |
| `BILLING_SERVICE_URI` | `https://api.stawi.org/payment` |
| `CHECKOUT_SERVICE_URI` | `https://api.stawi.org/checkout` |
| `CHECKOUT_PUBLIC_BASE_URL` | `https://pay.stawi.org` |

## Pub/Sub (matching)

| Topic | Purpose |
|-------|---------|
| `opportunities-matching-events` | Frame default events |
| `opportunities-fanout` | Path A: worker → matching after embed |
| `opportunities-cv-embed` | CV embed stage push |

Cluster worker publish: `gcppubsub://stawi-opportunities/opportunities-fanout`.

## Extensions (product Neon)

```hcl
neon_extensions = [
  "uuid-ossp", "pg_stat_statements", "pg_trgm",
  "btree_gin", "btree_gist", "vector",
  "lakebase_text", "timescaledb",
]
```

Avoid: `pg_search`, `vectorscale`, crawl hypertables on Neon.

## Full cutover checklist

### Vault (cluster dual-write)

```bash
# From SM (operator):
gcloud secrets versions access latest \
  --secret=opportunities-matching-database-url \
  --project=stawi-opportunities

# Seed Vault path used by ExternalSecret product-neon-credentials-opportunities:
#   stawi/product-opportunities/common/product-neon
#   product_database_url = <pooled Neon URL>
```

### Worker

Cluster workers set `PRODUCT_DATABASE_URL` + `MATCHING_FANOUT_QUEUE_URL=gcppubsub://stawi-opportunities/opportunities-fanout` + `GOOGLE_CLOUD_PROJECT=stawi-opportunities`.

Grant GKE worker SA (or node SA) `roles/pubsub.publisher` on project `stawi-opportunities` for fan-out.

### Lakebase Search

1. Neon console → project → enable **Lakebase Search**.
2. Re-apply matching (or `CREATE EXTENSION lakebase_text`) and re-run migrate job.
3. Confirm `opportunities_search_bm25` index exists; API ranks with lakebase BM25.

### Cluster customer surface

- `opportunities-api` / `opportunities-matching` Helm `replicaCount: 0`
- Cluster HTTPRoutes for `/jobs` and `/matching` have empty `parentRefs` (detached)

## Verification gates

1. Matching Ready; product migrations applied; `lakebase_text` present when Lakebase Search enabled.
2. API Ready; `SEARCH_BACKEND=lakebase_text`; search returns ranked hits after data.
3. Worker dual-DB: one crawl → row in Neon `opportunities`.
4. SPA: `/matching/me/*` + discovery via `/opportunities` (not `/jobs`).
5. Neon has **no** `job_ingest_queue` / `url_frontier`.
6. Cluster API + matching scaled to zero; cluster gateway routes detached.

## Rollback

Before scale-to-zero: re-point edge to cluster gateway. After: treat Neon product as forward-only (greenfield).
