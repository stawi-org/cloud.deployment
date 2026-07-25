# Mirrored from GHCR into project AR (Cloud Run cannot pull private GHCR cache).
# v1.54.56+ ships Frame v2.0.12 (gcppubsub dual-URL); v1.54.53 was Frame 2.0.8.
image = "europe-west9-docker.pkg.dev/stawi-identity/apps/service-authentication:v1.54.56"
# Public edge (see docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname       = "accounts.stawi.org"
enable_domain_mapping = false # leave false: edge-lb-* owns public DNS (europe-west9 has no domain mapping)
