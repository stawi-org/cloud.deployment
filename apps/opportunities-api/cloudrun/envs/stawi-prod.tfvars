# GHCR packages are private; Cloud Run pulls from project AR mirror.
image = "europe-west1-docker.pkg.dev/stawi-opportunities/ghcr-mirror/opportunities-api:v8.0.214"
container_port = 8080
# Canonical public path (replaces /jobs).
resource_path  = "/opportunities"
memory         = "1Gi"
has_database   = false
neon_extensions = []
requested_audience_paths = ["/profile", "/tenancy"]
public_hostname = ""
