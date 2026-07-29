# Opportunities Cloud Run + Neon Implementation Plan

> **For agentic workers:** Execute task-by-task. Spec: `docs/superpowers/specs/2026-07-29-opportunities-cloudrun-neon-design.md`.

**Goal:** Deploy customer-facing opportunities-api + opportunities-matching to Cloud Run with a shared Neon product DB (lakebase_text search, path `/opportunities`), keep crawl on cluster CNPG with dual-DB worker.

**Architecture:** Matching owns Neon + product migrations + Pub/Sub product topics. API attaches to matching’s DATABASE_URL secrets. Worker uses CRAWL_DATABASE_URL + PRODUCT_DATABASE_URL. Reuse profile/files/redirect/notification/payment/checkout.

**Tech Stack:** OpenTofu, Cloud Run, Neon (lakebase_text/vector), Pub/Sub, Frame, Go (stawi.opportunities).

---

### Task 1: cloud.deployment — opportunities-matching app
### Task 2: cloud.deployment — opportunities-api app (shared DB)
### Task 3: Edge routes, secret catalog, neon docs, DEPLOY_OPPORTUNITIES.md
### Task 4: stawi.opportunities — dual-DB jobqueue Store + worker config
### Task 5: stawi.opportunities — lakebase_text search + /opportunities API aliases
### Task 6: Product migration SQL for search_tsv + lakebase_bm25
### Task 7: Commit cloud.deployment; document cutover for manifests

---
