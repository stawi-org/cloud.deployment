image           = "ghcr.io/antinvestor/service-authentication-audit:v1.54.66"
# Match Cloud Run / Frame HTTP_PORT defaults used by other identity apps.
container_port  = 8080
resource_path   = "/audit"
memory          = "512Mi"
has_database    = true
neon_extensions = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
public_hostname = ""  # product surface: api.stawi.org/<path> only
