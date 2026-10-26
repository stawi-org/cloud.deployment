image                    = "ghcr.io/antinvestor/service-notification-ussd:v1.23.1"
resource_path            = "/ussd"
has_database             = true
memory                   = "512Mi"
requested_audience_paths = ["/profile", "/notification", "/seed"]
public_hostname          = ""
neon_extensions          = ["uuid-ossp", "pg_stat_statements"]
