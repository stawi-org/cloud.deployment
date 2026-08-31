image                    = "ghcr.io/stawilabs/stawi.imports-api:v0.1.0"
platform                 = "stawi-prod"
resource_path            = "/imports"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/tenancy", "/trustage"]
neon_extensions          = ["uuid-ossp", "pg_stat_statements", "pg_trgm"]
