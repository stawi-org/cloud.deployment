image                    = "ghcr.io/antinvestor/service-payment-ledger:v0.5.104"
resource_path            = "/ledger"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
