image                    = "ghcr.io/antinvestor/service-fintech-operations:v1.96.32"
resource_path            = "/operations"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/ledger", "/payment", "/notification", "/audit", "/identity", "/limits", "/loans", "/savings", "/funding", "/trustage"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
