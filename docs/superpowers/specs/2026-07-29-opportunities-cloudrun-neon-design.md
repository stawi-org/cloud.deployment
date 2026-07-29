# Opportunities → Cloud Run + Neon (customer surface only)

**Status:** approved — implementation in progress  
**Date:** 2026-07-29  
**Repos:** `cloud.deployment`, `stawi.opportunities`, `deployment.manifests` (cutover)  
**Depends on:** opportunities GCP/Neon onboard PRs #15/#16 (merged)

---

## 1. Goal

Move the **customer-facing** opportunities product to **Cloud Run + Neon**, keep the **crawl backend on the cluster**, and place **only high-value product data** on Neon so cost stays manageable.

This is a **greenfield full cutover**: product schema and traffic move cleanly; crawl stays on CNPG; cluster API + matching are scaled to zero after Cloud Run is healthy.

---

## 2. Decisions (locked)

| Decision | Choice |
|----------|--------|
| Customer Cloud Run services | `opportunities-api` + `opportunities-matching` only |
| Applications binary | Out of scope this phase |
| Crawl / pipeline | Remains on cluster (crawler, frontier-worker, worker-*, writer, materializer, NATS, Trustage crawl schedules) |
| Database | **Split:** Neon = product SoT; CNPG = crawl/ingest only |
| Neon ownership | Matching owns Neon project; API attaches same `DATABASE_URL` |
| Cluster API + matching after cutover | Scale to zero; remove cluster HTTPRoutes |
| Public API path | **`/jobs` → `/opportunities`** (canonical); temporary compat redirects |
| Full-text search on Neon | **`lakebase_text`** (not `pg_search`) |
| Vector ANN (matching / embeddings) | Prefer **`lakebase_vector`** (`lakebase_ann`) when Lakebase Search is enabled; fallback `pgvector` HNSW only if Lakebase ANN not available on the project |
| Service reuse | **No duplicated platform responsibilities** — call existing Stawi services |

---

## 3. Principles

### 3.1 Single responsibility / reuse

Opportunities owns **domain product logic only**. Everything else is delegated:

| Concern | Own? | Reuse |
|---------|------|--------|
| Identity / OIDC / JWT | No | Hydra + auth (`accounts.stawi.org`, `oauth2.stawi.org`) |
| Authorization | No | Keto (`authz.stawi.org`) |
| User profile (core person record) | No | `identity-profile` → `https://api.stawi.org/profile` |
| Tenancy | No | `identity-tenancy` → `/tenancy` |
| CV / attachment **bytes** | No | `platform-files` → `/files` (store `file_id` only) |
| Apply-link short URLs | No | `operations-redirect` → `/redirect` |
| Email / SMS / push delivery | No | `communications-notification` → `/notification` |
| Payment rails / capture | No | `payment-payment` + rails → `/payment` |
| Hosted checkout | No | `checkout-checkout` → `/checkout` (public `pay.stawi.org`) |
| Ledger / org billing product | No | `ledger-billing` → `/billing` (do not invent a second billing product) |
| Geo resolution (if needed later) | No | `platform-geolocation` → `/geolocation` |
| Scheduled digests / ops cron | Prefer reuse | Trustage on cluster **or** Cloud Scheduler → authenticated HTTPS; do not invent a third scheduler stack |
| Job **crawl** / extract / frontier | Yes (cluster) | Domain-owned pipeline |
| Opportunity **catalog** search & detail | Yes (Cloud Run API) | Domain-owned serving |
| Placement, matches, product entitlements cache | Yes (Cloud Run matching) | Domain-owned; money SoT remains payment/checkout |
| Pub/Sub for product async | Yes (GCP project) | Same Frame pattern as payments/comms |

**Anti-patterns (forbidden in this migration):**

- Second file store for CVs (no private R2-as-primary for user blobs; R2 archive remains crawl/ops only).
- Second notification pipeline (matching only builds templates + `NotificationService.Send`).
- Second payment gateway (only product checkout ledger + webhook entitlement cache).
- `pg_search` / ParadeDB on Neon.
- Re-exposing crawl admin on the public Cloud Run API.
- Putting crawl queues / frontier / ingest events on Neon.

### 3.2 Cost

- Neon holds **high-value, relatively durable** product rows only.
- High-churn crawl WAL, queues, and short-retention hypertables stay on **CNPG**.
- Neon CU caps remain low (existing module defaults); scale-to-zero friendly search via Lakebase where applicable.
- One Neon project for product (not one per binary).

### 3.3 Robustness

- Worker: **never ack crawl work** until product write commits (or durable outbox on crawl DB).
- Dual-DB explicit env names; no silent single-URL fallback in production.
- Edge path rename is coordinated with OAuth audience + SPA + docs.
- Cutover is checklist-driven with smoke gates before cluster scale-down.

---

## 4. Target topology

```text
                         Cloudflare edge
            api.stawi.org  +  (optional) jobs.stawi.org → opportunities
         ┌────────────────────┴────────────────────┐
         │ /opportunities  →  Cloud Run API          │
         │ /matching       →  Cloud Run matching     │
         └────────────────────┬────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    │
   opportunities-api   opportunities-matching      │
   (search, detail)    (candidates, matches,       │
                        billing webhooks, CV/chat) │
         │                    │                    │
         └──────────┬─────────┘                    │
                    ▼                              │
            PRODUCT Neon (stawi-opportunities org) │
            catalog + candidates + matches + $cache│
                    ▲                              │
                    │ PRODUCT_DATABASE_URL           │
                    │                              │
            Cluster worker (dual-DB)               │
                    │ CRAWL_DATABASE_URL             │
                    ▼                              │
            CNPG product-opportunities-db          │
            sources, recipes, runs, frontier,      │
            ingest queue + events                  │
                    ▲                              │
     crawler / frontier / NATS / Trustage (cluster)│
                                                   │
     Reused HTTPS services ────────────────────────┘
     profile, files, redirect, notification,
     payment, checkout, (ledger billing if needed)
```

---

## 5. Path migration: `/jobs` → `/opportunities`

### 5.1 Canonical public API

| Before | After (canonical) |
|--------|-------------------|
| Gateway prefix `/jobs` | Gateway prefix **`/opportunities`** |
| OAuth `resourcePath: /jobs` | OAuth **`resourcePath: /opportunities`** |
| Edge Worker route `prefix: /jobs` | Edge route **`prefix: /opportunities`** |
| SPA / docs referring to `/jobs` | Update to `/opportunities` |

Internal handler paths on the API binary may keep `/api/search`, `/api/jobs/{slug}` **or** be renamed to `/api/opportunities/{slug}` in the same release. Prefer **rename handlers** for consistency:

| Handler (binary) | New path (after gateway strip of `/opportunities`) |
|------------------|-----------------------------------------------------|
| Search | `GET /api/search` (unchanged relative) |
| Detail by slug | `GET /api/opportunities/{slug}` |
| Health | `GET /healthz` |

Public URLs after strip:

- `https://api.stawi.org/opportunities/api/search`
- `https://api.stawi.org/opportunities/api/opportunities/{slug}`

If the gateway strip + backend path convention for other services is “prefix maps to service root”, document the exact mount in `DEPLOY_OPPORTUNITIES.md` so SPA and OAuth stay aligned. **Requirement:** one canonical public prefix **`/opportunities`**, zero long-term dual public prefixes.

### 5.2 Compatibility window

During cutover only (documented max ~14 days, preferably shorter for greenfield):

1. Edge may serve **`/jobs` → 308 to `/opportunities`** (path-preserving) **or** dual route to the same origin with deprecation logs.
2. Hydra: register **`/opportunities`** audience; keep `/jobs` only if existing clients require it, then delete.
3. Host `jobs.stawi.org`: either CF CNAME → Cloud Run API or 308 → `https://api.stawi.org/opportunities/…` / marketing site; do not leave a second untracked origin.

### 5.3 Matching path

**`/matching` stays** (already product-correct; SPA uses `api.stawi.org/matching`). No rename.

### 5.4 Repo / docs touch list (comprehensive)

- `deployment.manifests` HTTPRoutes (remove `/jobs` after cutover).
- `cloud.deployment` edge `routes.prod.json`.
- opportunities-api Helm/Cloud Run `resource_path`.
- SPA (`opportunities.stawi.org`) API base URLs.
- `docs/api-reference.md`, end-user checklists, OAuth client config, any Keto resource names keyed on `/jobs`.

---

## 6. Data split

### 6.1 Neon product (high value)

| Domain | Tables (indicative) |
|--------|---------------------|
| Catalog | `opportunity_identities`, `opportunities`, `opportunity_sources`, `companies`, `opportunity_flags` |
| Search support | generated `search_tsv` (tsvector) + `lakebase_bm25` index; embedding column + ANN index |
| Candidates | `candidate_profiles` (product fields + entitlement cache), placement profiles, preferences, match rules |
| Matching | `candidate_match_indexes`, `candidate_matches`, `candidate_saved_jobs` |
| Events (bounded) | match/engagement hypertables **with retention jobs** (Timescale Apache-2; no compression on Neon) |
| Billing cache | `candidate_checkouts`, profile `subscription` / `plan_id` / `subscription_id` |

### 6.2 CNPG crawl only (not on Neon)

| Domain | Tables |
|--------|--------|
| Control | `sources`, `source_recipes`, `crawl_runs`, `host_state` |
| Work | `url_frontier`, `job_ingest_queue` |
| Ops audit | `crawl_jobs`, `job_ingest_events` (+ short retention) |

### 6.3 Explicit non-goals on Neon

- Raw HTML / archive bodies (R2)
- NATS / JetStream state
- Valkey debounce keys (optional Valkey later; not Neon)
- Materializer / Manticore (already retired for serving)

### 6.4 Shared Neon wiring

- **`opportunities-matching`**: `has_database = true`, creates Neon project, runs product migrations, enables extensions.
- **`opportunities-api`**: `has_database = false`, mounts **same** Secret Manager secrets (`*-database-url` / direct) from matching (Terraform remote state or explicit shared secret resource — pick one pattern in implementation; prefer remote state output → data source to avoid secret duplication).
- **Cluster worker**: `CRAWL_DATABASE_URL` + `PRODUCT_DATABASE_URL` (both required in prod).

---

## 7. Search: `pg_search` → `lakebase_text`

Today API search uses ParadeDB/`pg_search` (`canonical_id @@@ paradedb.parse(...)`, `paradedb.score`). **Neon forbids new `pg_search` installs** and removes existing by Sept 2026. Replacement: **`lakebase_text`**.

### 7.1 Schema (product Neon)

```sql
-- Enable once per project (requires Lakebase Search on the Neon project)
CREATE EXTENSION IF NOT EXISTS lakebase_text;

ALTER TABLE opportunities
  ADD COLUMN IF NOT EXISTS search_tsv tsvector
  GENERATED ALWAYS AS (
    to_tsvector(
      'english',
      coalesce(title, '') || ' ' ||
      coalesce(company_name, '') || ' ' ||  -- use actual column names from schema
      coalesce(description_text, '') || ' ' ||
      coalesce(location_text, '')
    )
  ) STORED;

-- After initial load / migrate:
CREATE INDEX opportunities_search_bm25
  ON opportunities USING lakebase_bm25 (search_tsv)
  WITH (default_limit = 50);
```

(Exact column list must match the live `opportunities` serving row; adjust in migration SQL.)

### 7.2 Query rewrite (API)

| pg_search | lakebase_text |
|-----------|----------------|
| `col @@@ paradedb.parse($q)` | `search_tsv @@ websearch_to_tsquery('english', $q)` **and** rank with `<@>` |
| `paradedb.score(id) DESC` | `search_tsv <@> to_bm25query(to_tsvector('english', $q), 'opportunities_search_bm25') ASC` |
| Fuzzy | `pg_trgm` if needed |
| Snippets | `ts_headline` |

Empty `q` keeps current browse/filter listing (no BM25).

Session GUCs for hot path (or index storage params):

- `lakebase_bm25.default_limit` ≈ query `LIMIT`
- `lakebase_bm25.prefilter = on` when facet filters are selective

### 7.3 Vector / hybrid (matching + future hybrid search)

- Enable **`lakebase_vector`** with Lakebase Search on the same project when using ANN at scale.
- Opportunity and candidate embeddings remain `vector(1024)` (current model dim); migrate HNSW → `lakebase_ann` if recommended by Neon for scale-to-zero.
- Hybrid search (BM25 + cosine) is a **follow-up** after BM25 parity; do not block cutover on hybrid.

### 7.4 Neon module / bootstrap

- Document Lakebase Search enablement (Neon API / console: preload libraries) **before** `CREATE EXTENSION`.
- `neon_extensions` for matching product DB:  
  `uuid-ossp`, `pg_stat_statements`, `pg_trgm`, `btree_gin`, `btree_gist`, `vector`, `lakebase_text`, optionally `lakebase_vector`, `timescaledb`, `postgis` only if a geo column is actually used.
- **Never** list `pg_search` or `vectorscale` for this project.
- Update `modules/neon-database` docs comment to name `lakebase_text` as the BM25 path.

---

## 8. Application changes (`stawi.opportunities`)

### 8.1 Dual-DB worker

1. **Crawl DB:** claim `job_ingest_queue`, write ingest events, manage leases.
2. **Product DB:** hard_key resolve, upsert `opportunities` + `opportunity_sources`, visibility.
3. **Commit order:** product commit → crawl ack. On product failure: retry / dead-letter; do not ack.
4. Env: `CRAWL_DATABASE_URL`, `PRODUCT_DATABASE_URL` (fail boot if either missing when `DUAL_DB=true`).
5. Embeds / fan-out publish after product write: **Pub/Sub** topic consumed by Cloud Run matching.

### 8.2 API (Cloud Run)

- Product DB only.
- `SOURCE_ADMIN_ENABLED=false` (crawl admin stays on cluster crawler/api admin if retained).
- Search backend: **lakebase_text** only on Neon path (remove `pg_search` code path for cloud builds or feature-flag `SEARCH_BACKEND=lakebase_text|pg_search` with Neon default `lakebase_text`).
- Path rename per §5.
- No local file, payment, or notification stacks.

### 8.3 Matching (Cloud Run)

- Product DB only; migrations owner for product schema.
- Service URIs (HTTPS, public gateway — not cluster DNS):

  | Env | Value |
  |-----|--------|
  | `PROFILE_SERVICE_URI` | `https://api.stawi.org/profile` |
  | `FILE_SERVICE_URI` | `https://api.stawi.org/files` |
  | `REDIRECT_SERVICE_URI` | `https://api.stawi.org/redirect` |
  | `NOTIFICATION_SERVICE_URI` | `https://api.stawi.org/notification` |
  | `BILLING_SERVICE_URI` / payment | `https://api.stawi.org/payment` |
  | `CHECKOUT_SERVICE_URI` | `https://api.stawi.org/checkout` |
  | `CHECKOUT_PUBLIC_BASE_URL` | `https://pay.stawi.org` |
  | `PUBLIC_SITE_URL` | `https://opportunities.stawi.org` |

- Messaging: **Pub/Sub** for CV pipeline + opportunity fan-out + internal digests (Frame `gcppubsub://stawi-opportunities/...`).
- OAuth `resource_path` remains `/matching`; requested audiences for profile, files, redirect, payment, notification, checkout as today.

### 8.4 Cluster crawl stack

- Continues on CNPG only (except worker dual-DB).
- After product tables no longer live on CNPG: stop AutoMigrate of product models on crawl binaries; optional migration to drop product tables from CNPG post-validation.

---

## 9. Cloud deployment layout

### 9.1 Apps

```text
apps/opportunities-matching/   # owns Neon, Pub/Sub topics, migrate job
apps/opportunities-api/        # attaches DB, lighter resources, no migrate
```

| | matching | api |
|--|----------|-----|
| `gcp.account` | opportunities | opportunities |
| `neon.account` | opportunities | opportunities (no project create) |
| Image | `ghcr.io/stawi-opportunities/opportunities-matching` | `.../opportunities-api` |
| Memory (start) | ≥1Gi (chat/CV/inference headroom) | 512Mi–1Gi |
| `resource_path` | `/matching` | **`/opportunities`** |
| Edge | `/matching` | **`/opportunities`** |

### 9.2 Secrets / catalog

- `config/secret-catalog/opportunities.yaml`: billing webhook, checkout internal token, inference, R2 (if still needed for archive admin — prefer not on API), hydra PSK mirror pattern (IAM only, no create if pre-seeded).
- Do not re-create identity `hydra-webhook-psk`; accessor + local copy pattern as payments/ops.

### 9.3 IAM / prerequisites

1. GCP project `stawi-opportunities` + Neon org already onboarded.
2. Deploy SA: WIF, R2 state, Neon API key via SOPS.
3. Cross-project: read identity Cloud Run for Hydra/Keto URIs if required by module; SM accessor on identity PSK.
4. Keto/Hydra allow-lists for opportunities runtime SAs (invoker + OAuth client registration).
5. Enable **Lakebase Search** on the Neon project before extension apply.

### 9.4 Docs

- `docs/DEPLOY_OPPORTUNITIES.md` — apply order, dual-DB, path rename, cutover checklist, rollback.
- Update `ADDING_AN_APP` / neon module notes for `lakebase_text`.
- This spec remains the architectural SoT until implemented.

---

## 10. Messaging design

| Flow | Owner | Mechanism |
|------|-------|-----------|
| Ingest claim / crawl wake | Cluster | NATS + CNPG (unchanged) |
| Worker → matching Path A fan-out | Matching topics in `stawi-opportunities` | Pub/Sub push → matching |
| CV extract / improve / embed | Matching | Pub/Sub (self-consume) |
| Digests / stale CV | Prefer Cloud Scheduler → matching admin HTTPS with shared secret **or** Trustage calling public URL | Not a new custom scheduler product |
| Notifications | Notification service | Already reused |

Topic naming: `opportunities-{purpose}` (e.g. `opportunities-fanout`, `opportunities-cv-embed`) with regional storage policy `europe-west1`.

---

## 11. Cutover sequence (thorough)

### Phase A — Code & images

1. Dual-DB worker + lakebase_text search + path rename + Pub/Sub consumers/producers in `stawi.opportunities`.
2. CI image tags; pin in tfvars.
3. SPA/docs OAuth updates for `/opportunities`.

### Phase B — Infrastructure

1. Confirm Neon Lakebase Search enabled.
2. `app-apply` **opportunities-matching** (Neon + extensions + migrate + Pub/Sub + secrets).
3. Share DB URL secret with **opportunities-api**; apply API + edge routes (`/opportunities`, `/matching`).
4. Seed hydra PSK / billing / checkout secrets per catalog.

### Phase C — Pipeline switch

1. Configure cluster worker with both DB URLs; roll worker.
2. Run one crawl source; assert row in **Neon** product tables; search via Cloud Run `/opportunities`.
3. Smoke matching: onboard, CV via files service, checkout, match write, notification path (template may be dry-run).

### Phase D — Traffic

1. Point CF edge `/opportunities` + `/matching` at Cloud Run.
2. 308 `/jobs` → `/opportunities` if needed.
3. Verify OAuth audience for `/opportunities`.
4. Remove cluster HTTPRoutes for jobs/matching; scale cluster API + matching to 0.

### Phase E — Cleanup

1. Drop product tables from CNPG (optional, after soak).
2. Remove `/jobs` compat routes and Hydra `/jobs` audience.
3. Confirm no `pg_search` extension on Neon.
4. Update runbooks; close cutover checklist.

### Phase F — Verification gates (must pass before scale-to-zero)

| Gate | Check |
|------|--------|
| Ready | Cloud Run Ready + secret mounts |
| Search | BM25 query returns ranked hits from lakebase_text |
| Browse | Empty-q listing + facets |
| Dual-write | Ingest → Neon opportunity visible |
| Matching | JWT `/matching/me/*` works |
| Files | CV upload stores via `/files` |
| Billing | Checkout session + webhook entitlement |
| Notify | Client call succeeds or documented skip |
| Cost | Neon has no `job_ingest_*` / `url_frontier` tables |

---

## 12. Rollback

- **Before scale-to-zero:** re-point edge to cluster; worker can stop product URL if needed.
- **After scale-to-zero:** re-enable cluster deployments from git history; product data on Neon may be ahead of CNPG — treat as forward-only after Phase D unless Neon is wiped (greenfield acceptable).
- Image pins allow Cloud Run revision rollback without schema downgrade if migrations are additive.

---

## 13. Out of scope (explicit)

- Cloud Run for crawler / frontier / worker / writer / materializer
- `apps/applications` deploy
- Migrating Hugo SPA hosting (stays as today)
- Hybrid BM25+vector public search (follow-up)
- Auto-apply agents
- Moving crawl to Neon “later” without a new cost review

---

## 14. Implementation workstreams

| # | Workstream | Primary repo |
|---|------------|--------------|
| W1 | Dual-DB worker + product migration ownership | stawi.opportunities |
| W2 | lakebase_text search + path rename `/opportunities` | stawi.opportunities |
| W3 | Matching Pub/Sub + HTTPS service URIs | stawi.opportunities |
| W4 | Terraform apps + secret catalog + edge routes | cloud.deployment |
| W5 | Neon Lakebase enable + extensions | cloud.deployment + ops |
| W6 | Cluster worker env + scale-down API/matching routes | deployment.manifests |
| W7 | SPA / OAuth / docs path updates | UI + docs |
| W8 | Cutover execution + verification | ops |

---

## 15. Success criteria

1. Public discovery only via **`/opportunities`** on Cloud Run + Neon product DB.  
2. Matching only via **`/matching`** on Cloud Run + same Neon DB.  
3. Crawl continues on cluster CNPG; **no crawl tables on Neon**.  
4. Search uses **`lakebase_text`**, not `pg_search`.  
5. Files, profile, payment, checkout, notification, redirect are **reused**, not reimplemented.  
6. Cluster API + matching scaled to zero after gates pass.  
7. Cost profile: one Neon product project; crawl write load stays off Neon.

---

## 16. Open items for implementation plan (non-blocking on design intent)

- Exact Terraform pattern for sharing Neon URL secret (remote state vs shared SM resource).  
- Precise `opportunities` column names for `search_tsv` generation (from live schema).  
- Whether digests use Cloud Scheduler or Trustage→HTTPS.  
- Host strategy for `jobs.stawi.org` (CNAME vs redirect).  

These are resolved during planning with defaults: remote state share; columns from migrations; Cloud Scheduler for digests; 308 `jobs.stawi.org` → public opportunities API or marketing site.
