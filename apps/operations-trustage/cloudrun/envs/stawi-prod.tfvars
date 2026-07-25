image                    = "europe-west9-docker.pkg.dev/stawi-identity/apps/service-trustage:v0.4.0"
container_port           = 8080
resource_path            = "/trustage"
memory                   = "768Mi"
has_database             = true
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist", "timescaledb"]
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname          = "trustage.stawi.org"
