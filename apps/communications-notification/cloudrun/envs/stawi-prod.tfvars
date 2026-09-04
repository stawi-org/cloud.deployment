image                    = "ghcr.io/antinvestor/service-notification:v1.21.61"
resource_path            = "/notification"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
