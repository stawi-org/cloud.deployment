image                    = "ghcr.io/antinvestor/service-fintech-stawi:v1.96.27"
resource_path            = "/stawi"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/identity", "/loans", "/savings", "/ledger", "/payment", "/notification", "/files", "/limits", "/audit", "/trustage"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
