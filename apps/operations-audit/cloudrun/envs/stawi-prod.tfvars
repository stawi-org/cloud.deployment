image           = "europe-west9-docker.pkg.dev/stawi-identity/apps/service-authentication-audit:v1.54.56"
container_port  = 80
resource_path   = "/audit"
memory          = "512Mi"
has_database    = true
neon_extensions = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist", "timescaledb"]
public_hostname = "audit.stawi.org"
