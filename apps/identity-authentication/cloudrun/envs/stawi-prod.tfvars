# Public GHCR image (Cloud Run pulls ghcr.io directly; no AR mirror).
# v1.54.63 = Frame v2.1.3 (ext.roles array parse for SA internal role). Avoid v1.54.62 (Frame 2.1.0).
image = "ghcr.io/antinvestor/service-authentication:v1.54.66"
# Public edge (see docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname       = "accounts.stawi.org"
