image = "oryd/hydra:v2.2.0"
# Public edge (see docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname           = "oauth2.stawi.org"
enable_domain_mapping = false # leave false: edge-lb-* owns public DNS (europe-west9 has no domain mapping)
advertise_public_hostname = false # true after Cloudflare CNAME cutover to domain mapping
