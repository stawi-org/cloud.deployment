image                    = "ghcr.io/antinvestor/service-fintech-seed:v1.96.27"
resource_path            = "/seed"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/identity", "/loans", "/operations", "/audit"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
