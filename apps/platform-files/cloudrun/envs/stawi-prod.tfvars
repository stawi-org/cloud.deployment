image = "europe-west9-docker.pkg.dev/stawi-platform/apps/service-files:v1.10.54"

# Public edge (docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname       = "files.stawi.org"
enable_domain_mapping = false # leave false: edge-lb-* owns public DNS (europe-west9 has no domain mapping)
