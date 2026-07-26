# Public GHCR image (Cloud Run pulls ghcr.io directly; no AR mirror).
# v1.54.56+ ships Frame v2.0.12 (gcppubsub dual-URL); v1.54.53 was Frame 2.0.8.
image = "ghcr.io/antinvestor/service-authentication:v1.54.62"
# Public edge (see docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname       = "accounts.stawi.org"
