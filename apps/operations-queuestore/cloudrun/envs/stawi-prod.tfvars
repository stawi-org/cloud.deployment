image                    = "ghcr.io/antinvestor/service-trustage-queue:v0.3.62"
container_port           = 8082
resource_path            = "/queuestore"
memory                   = "512Mi"
has_database             = true
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname          = "queuestore.stawi.org"
