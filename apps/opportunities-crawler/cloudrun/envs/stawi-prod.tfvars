# Crawl Neon ownership. Mirror GHCR → AR before first apply if needed:
#   gcloud artifacts docker tags list .../ghcr-mirror/opportunities-crawler
image = "europe-west1-docker.pkg.dev/stawi-opportunities/ghcr-mirror/opportunities-crawler:v8.0.211"
container_port = 8080
resource_path  = ""
memory         = "512Mi"
has_database   = true
# Crawl DB: queues, frontier, sources, Timescale audit — not product catalog.
# No lakebase_text (product search stays on matching Neon).
neon_extensions = [
  "uuid-ossp",
  "pg_stat_statements",
  "pg_trgm",
  "btree_gin",
  "btree_gist",
  "timescaledb",
  "vector",
]
requested_audience_paths = []
public_hostname = ""
