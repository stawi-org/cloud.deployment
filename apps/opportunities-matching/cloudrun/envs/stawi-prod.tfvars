# Public GHCR — Cloud Run pulls ghcr.io directly (no AR mirror).
image = "ghcr.io/stawi-opportunities/opportunities-matching:v8.0.215"
container_port = 8080
resource_path = "/matching"
memory        = "1Gi"
has_database  = true
# Product Neon: high-value data only. lakebase_text replaces pg_search.
# lakebase_vector optional after Lakebase Search is enabled on the project.
# lakebase_text: requires Lakebase Search enabled on the Neon project
# (console/API). CREATE EXTENSION is soft-failed by migrate SQL if missing;
# API then ranks with ts_rank until BM25 index exists.
neon_extensions = [
  "uuid-ossp",
  "pg_stat_statements",
  "pg_trgm",
  "btree_gin",
  "btree_gist",
  "vector",
  "timescaledb",
  "lakebase_text",
]
requested_audience_paths = [
  "/profile",
  "/tenancy",
  "/files",
  "/redirect",
  "/notification",
  "/payment",
  "/checkout",
  "/chat-agent",
]
public_hostname = ""
