image                    = "ghcr.io/antinvestor/service-manufacturing:v0.2.0"
resource_path            = "/manufacturing"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
