image                    = "ghcr.io/antinvestor/service-payment-checkout:v0.5.111"
resource_path            = "/checkout"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/payment"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
