# Bootstrap image in project AR. Routine rolls via cloudrun-ship (tofu ignores image).
image = "europe-west9-docker.pkg.dev/stawi-identity/apps/service-fintech-identity:v1.96.16"

# Public edge (docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname       = "identity.stawi.org"
enable_domain_mapping = false # true after: gcloud domains verify stawi.org
