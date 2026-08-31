# Crawl Neon ownership. Public GHCR — Cloud Run pulls ghcr.io directly.
image = "ghcr.io/stawi-opportunities/opportunities-crawler:v8.0.211"
container_port = 8080
resource_path  = ""
memory         = "512Mi"
has_database   = true
# Crawl DB: queues, frontier, sources, append-only audit — not product catalog.
# No lakebase_text (product search stays on matching Neon).
neon_extensions = [
  "uuid-ossp",
  "pg_stat_statements",
  "pg_trgm",
  "btree_gin",
  "btree_gist",
  "vector",
]
requested_audience_paths = []
public_hostname = ""
