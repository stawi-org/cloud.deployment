# Deploy opportunities (Cloud Run product + cluster crawl)

**Split databases (locked):**

| Plane | Runtime | Database | Owner |
|-------|---------|----------|-------|
| Product | Cloud Run | **Neon product** | matching migrations |
| Crawl / ingest | Cluster `product-opportunities` | **CNPG crawl** | crawler migrations |

Shared surfaces only: worker dual-DB catalog write + Pub/Sub fan-out. See design spec and cluster cutover notes.

| Account | Project / org |
|---------|----------------|
| GCP `opportunities` | `stawi-opportunities` (europe-west1) |
| Neon `opportunities` | product project via matching module |

**Spec:** [superpowers/specs/2026-07-29-opportunities-cloudrun-neon-design.md](superpowers/specs/2026-07-29-opportunities-cloudrun-neon-design.md)  
**Cluster:** `deployment.manifests` `namespaces/product-opportunities/common/CUTOVER_CLOUD_RUN.md`  
**App DB contract:** `stawi.opportunities` `docs/ops/db-boundaries.md`

## Applications (Cloud Run — product)

| App directory | Role | Neon | Public path | Image pin (prod) |
|---------------|------|------|-------------|------------------|
| `opportunities-matching` | Candidates, matches, CV/chat, billing webhooks; **owns product Neon** | yes (owner) | `/matching` | `v8.0.211` (latest AR) |
| `opportunities-api` | Public search + detail; attaches matching DB secret | shared | **`/opportunities`** | `v8.0.213` |

## Cluster job plane (crawl only)

| Workload | Role | Database |
|----------|------|----------|
| crawler | Sources, schedules, structured crawl, admit/enqueue | CNPG only |
| frontier-worker | URL frontier claim/fetch | CNPG only |
| worker | Drain `job_ingest_queue` → product catalog write | **dual:** CNPG + Neon |
| NATS | Wake-ups / control (not job SoT) | — |

**Do not deploy on cluster:** api, matching, materializer, writer, worker-core/validate/publish.

### Worker env (required in prod)

```text
DATABASE_URL              → CNPG pooler (crawl queue claim/ack)
PRODUCT_DATABASE_URL      → Neon product (catalog)
MATCHING_FANOUT_QUEUE_URL → gcppubsub://stawi-opportunities/opportunities-fanout
GOOGLE_CLOUD_PROJECT      → stawi-opportunities
```

## Data split

| On Neon (product) | On CNPG (crawl) |
|-------------------|-----------------|
| catalog, companies, flags | sources, recipes, crawl_runs, host_state |
| candidates, matches, applications | url_frontier, job_ingest_queue |
| billing entitlement cache | crawl_jobs, job_ingest_events |

Search on Neon uses **`lakebase_text`** (BM25), not `pg_search`.

## Path migration

| Old | New (canonical) |
|-----|-----------------|
| `/jobs` | **`/opportunities`** |
| OAuth resource `/jobs` | **`/opportunities`** |
| `/matching` | `/matching` (unchanged) |

## Prerequisites

1. GCP + Neon onboard for `opportunities`.
2. Lakebase Search enabled on the Neon product project when using BM25.
3. Seed SM: `hydra-webhook-psk`, `billing-webhook-secret`, `checkout-internal-token`.
4. Cluster: CNPG ready; secret `product-neon-credentials-opportunities` for worker.
5. Images: GHCR `ghcr.io/stawi-opportunities/opportunities-{api,matching,crawler,worker,frontier-worker}:vX.Y.Z`.

## Apply order

```text
1. identity (Hydra/Keto) already live
2. opportunities-matching   # Neon + product migrations + Pub/Sub
3. opportunities-api        # shared DB secret + edge /opportunities
4. Cluster CNPG + NATS
5. Crawler migrate (CNPG) + crawler/frontier/worker dual-DB
6. Smoke gates
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

## Extensions (product Neon)

```hcl
neon_extensions = [
  "uuid-ossp", "pg_stat_statements", "pg_trgm",
  "btree_gin", "btree_gist", "vector",
  "lakebase_text", "timescaledb",
]
```

Avoid: `pg_search`, crawl queue tables on Neon.

## Verification gates

1. Matching Ready; product migrations applied.
2. API Ready; search returns ranked hits when data present.
3. Worker dual-DB log line; one crawl → row in Neon `opportunities`.
4. SPA: `/matching/me/*` + discovery via `/opportunities`.
5. Neon has **no** crawl SoT requirement for `job_ingest_queue` / `url_frontier`.
6. Cluster runs only crawler + frontier-worker + worker (+ CNPG + NATS).

## Rollback

Before scale-to-zero of cluster product surface: already on Cloud Run.  
Crawl rollback: keep CNPG; pause schedules via crawler admin.
