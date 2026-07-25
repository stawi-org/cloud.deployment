image = "europe-west9-docker.pkg.dev/stawi-platform/apps/service-profile-settings:v1.53.5"

# Public edge (docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname       = "settings.stawi.org"
enable_domain_mapping = false # true after: gcloud domains verify stawi.org
