# Deploy opportunities (Cloud Run product + cluster crawl)

**Two Neon projects (locked):**

| Plane | Runtime | Neon project (SM secret) | Schema owner |
|-------|---------|--------------------------|--------------|
| Product | Cloud Run | `opportunities-matching-database-url` | matching migrate |
| Crawl | Cluster jobs | `opportunities-crawler-database-url` | crawler migrate |

Shared surfaces only: worker dual-DB catalog write + Pub/Sub fan-out.

| Account | Project / org |
|---------|----------------|
| GCP `opportunities` | `stawi-opportunities` (europe-west1) |
| Neon `opportunities` | both Neon projects in the opportunities Neon org |

**Spec:** [superpowers/specs/2026-07-29-opportunities-cloudrun-neon-design.md](superpowers/specs/2026-07-29-opportunities-cloudrun-neon-design.md) (crawl DB host updated: Neon, not CNPG)  
**Cluster:** `deployment.manifests` `namespaces/product-opportunities/common/CUTOVER_CLOUD_RUN.md`  
**App DB contract:** `stawi.opportunities` `docs/ops/db-boundaries.md`

## Applications

### Cloud Run — product + crawl DB ownership

| App directory | Role | Neon | Public path | Image pin (prod) |
|---------------|------|------|-------------|------------------|
| `opportunities-matching` | Candidates, matches, CV/chat, billing; **owns product Neon** | product | `/matching` | `v8.0.211` |
| `opportunities-api` | Public search + detail; attaches **product** Neon | product (shared) | **`/opportunities`** | `v8.0.213` |
| `opportunities-crawler` | **Owns crawl Neon** + migrate Job; service min=0 | crawl | none (private) | `v8.0.211` |

### Cluster job plane (uses crawl Neon)

| Workload | Role | `DATABASE_URL` | `PRODUCT_DATABASE_URL` |
|----------|------|----------------|------------------------|
| crawler | Sources, schedules, structured crawl | crawl Neon | unset |
| frontier-worker | URL frontier claim/fetch | crawl Neon | unset |
| worker | Drain ingest → catalog write | crawl Neon | **product Neon** |
| NATS | Wake-ups only (not job SoT) | — | — |

**Do not deploy on cluster:** api, matching, materializer, writer, worker-core/validate/publish, CNPG.

### Worker env (required in prod)

```text
DATABASE_URL              → crawl Neon (opportunities-crawler-database-url)
PRODUCT_DATABASE_URL      → product Neon (opportunities-matching-database-url)
MATCHING_FANOUT_QUEUE_URL → gcppubsub://stawi-opportunities/opportunities-fanout
GOOGLE_CLOUD_PROJECT      → stawi-opportunities
```

## Data split

| On product Neon | On crawl Neon |
|-----------------|---------------|
| catalog, companies, flags | sources, recipes, crawl_runs, host_state |
| candidates, matches, applications | url_frontier, job_ingest_queue |
| billing entitlement cache | crawl_jobs, job_ingest_events |

Search on **product** Neon uses **`lakebase_text`**. Crawl Neon uses Timescale for audit/queues only.

## Apply order

```text
1. identity already live
2. opportunities-matching   # product Neon + migrations + Pub/Sub
3. opportunities-crawler    # crawl Neon + migrations
4. opportunities-api        # product Neon secret + edge /opportunities
5. Seed k8s secrets from SM → cluster crawler/frontier/worker
6. Flux crawl plane (no CNPG)
7. Smoke gates
```

```bash
gh workflow run app-apply.yml -f app=opportunities-matching -f env=stawi-prod
gh workflow run app-apply.yml -f app=opportunities-crawler -f env=stawi-prod
gh workflow run app-apply.yml -f app=opportunities-api -f env=stawi-prod
```

### Seed cluster dual Neon secrets

```bash
CRAWL=$(gcloud secrets versions access latest \
  --secret=opportunities-crawler-database-url \
  --project=stawi-opportunities)
PRODUCT=$(gcloud secrets versions access latest \
  --secret=opportunities-matching-database-url \
  --project=stawi-opportunities)

kubectl -n product-opportunities create secret generic crawl-neon-credentials-opportunities \
  --from-literal=DATABASE_URL="$CRAWL" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n product-opportunities create secret generic product-neon-credentials-opportunities \
  --from-literal=PRODUCT_DATABASE_URL="$PRODUCT" --dry-run=client -o yaml | kubectl apply -f -
```

## Path migration

| Old | New (canonical) |
|-----|-----------------|
| `/jobs` | **`/opportunities`** |
| `/matching` | `/matching` |

## Reused services

| Env | URL |
|-----|-----|
| `PROFILE_SERVICE_URI` | `https://api.stawi.org/profile` |
| `FILE_SERVICE_URI` | `https://api.stawi.org/files` |
| `REDIRECT_SERVICE_URI` | `https://api.stawi.org/redirect` |
| `NOTIFICATION_SERVICE_URI` | `https://api.stawi.org/notification` |
| `BILLING_SERVICE_URI` | `https://api.stawi.org/payment` |
| `CHECKOUT_SERVICE_URI` | `https://api.stawi.org/checkout` |
| `CHECKOUT_PUBLIC_BASE_URL` | `https://pay.stawi.org` |

## Pub/Sub (matching / product)

| Topic | Purpose |
|-------|---------|
| `opportunities-matching-events` | Frame default events |
| `opportunities-fanout` | Path A: worker → matching after embed |
| `opportunities-cv-embed` | CV embed stage |

## Extensions

**Product Neon** (`opportunities-matching`):

```hcl
neon_extensions = [
  "uuid-ossp", "pg_stat_statements", "pg_trgm",
  "btree_gin", "btree_gist", "vector",
  "lakebase_text", "timescaledb",
]
```

**Crawl Neon** (`opportunities-crawler`):

```hcl
neon_extensions = [
  "uuid-ossp", "pg_stat_statements", "pg_trgm",
  "btree_gin", "btree_gist", "timescaledb", "vector",
]
```

Avoid: `pg_search`; product tables as crawl SoT; crawl queues as product SoT.

## Verification

1. Matching Ready; product migrations applied.
2. Crawler migrate Job Ready; crawl Neon has sources/queue tables.
3. API Ready on product Neon.
4. Worker dual-DB log; one crawl → row in **product** Neon `opportunities`.
5. Crawl Neon holds queue/frontier; product Neon holds catalog/candidates.
6. Cluster runs only crawler + frontier-worker + worker (+ NATS). No CNPG.
