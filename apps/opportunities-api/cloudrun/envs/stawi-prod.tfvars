image          = "ghcr.io/stawi-opportunities/opportunities-api:v8.0.210"
container_port = 8080
# Canonical public path (replaces /jobs).
resource_path  = "/opportunities"
memory         = "1Gi"
has_database   = false
neon_extensions = []
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname = ""
