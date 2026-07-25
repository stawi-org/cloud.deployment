image                    = "europe-west9-docker.pkg.dev/stawi-identity/apps/service-trustage-formstore:v0.3.62"
container_port           = 8081
resource_path            = "/formstore"
memory                   = "512Mi"
has_database             = true
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname          = "formstore.stawi.org"
