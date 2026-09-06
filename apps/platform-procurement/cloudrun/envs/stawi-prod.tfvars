image                    = "ghcr.io/antinvestor/service-commerce-procurement:v0.4.2"
resource_path            = "/procurement"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy"]
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
