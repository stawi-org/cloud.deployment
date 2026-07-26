image                    = "europe-west9-docker.pkg.dev/stawi-identity/apps/service-files-redirect:v1.10.56"
container_port           = 80
resource_path            = "/redirect"
memory                   = "512Mi"
has_database             = true
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm", "btree_gin", "btree_gist"]
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname          = "redirect.stawi.org"
