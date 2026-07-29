image                    = "ghcr.io/antinvestor/service-fintech-limits:v1.96.22"
resource_path            = "/limits"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/ledger", "/payment"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
