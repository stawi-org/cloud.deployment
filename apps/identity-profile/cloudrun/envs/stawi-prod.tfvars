# Bootstrap image in project AR. Routine rolls via cloudrun-ship (tofu ignores image).
image = "europe-west9-docker.pkg.dev/stawi-identity/apps/service-profile:v1.53.7"

# Public edge (docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname       = "profile.stawi.org"
