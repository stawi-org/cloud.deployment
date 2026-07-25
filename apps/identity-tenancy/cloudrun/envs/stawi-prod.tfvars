# Bootstrap image in project AR. Routine rolls via cloudrun-ship (tofu ignores image).
image = "europe-west9-docker.pkg.dev/stawi-identity/apps/service-authentication-tenancy:v1.54.56"

# Public edge (docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname       = "tenancy.stawi.org"
enable_domain_mapping = false # leave false: edge-lb-* owns public DNS (europe-west9 has no domain mapping)
