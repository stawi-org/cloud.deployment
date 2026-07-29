image         = "ghcr.io/stawi-opportunities/opportunities-matching:v8.0.211"
container_port = 8080
resource_path = "/matching"
memory        = "1Gi"
has_database  = true
# Product Neon: high-value data only. lakebase_text replaces pg_search.
# lakebase_vector optional after Lakebase Search is enabled on the project.
# lakebase_text requires Lakebase Search enabled on the Neon project first.
# Applied in a follow-up once CREATE EXTENSION lakebase_text succeeds; until
# then API SEARCH_BACKEND falls back if BM25 unavailable.
neon_extensions = [
  "uuid-ossp",
  "pg_stat_statements",
  "pg_trgm",
  "btree_gin",
  "btree_gist",
  "vector",
  "timescaledb",
]
requested_audience_paths = [
  "/profile",
  "/tenancy",
  "/files",
  "/redirect",
  "/notification",
  "/payment",
  "/checkout",
]
public_hostname = ""
