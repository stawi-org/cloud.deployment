image                    = "ghcr.io/antinvestor/service-fintech-funding:v1.96.32"
resource_path            = "/funding"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/ledger", "/payment", "/notification", "/audit", "/identity", "/limits", "/loans", "/operations", "/savings"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
