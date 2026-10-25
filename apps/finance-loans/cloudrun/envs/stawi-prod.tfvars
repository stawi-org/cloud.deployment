image                    = "ghcr.io/antinvestor/service-fintech-loans:v1.96.32"
resource_path            = "/loans"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/operations", "/notification", "/audit", "/funding", "/identity", "/limits", "/seed", "/trustage"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
