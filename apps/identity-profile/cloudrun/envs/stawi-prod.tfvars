# Bootstrap pin (public GHCR). Routine rolls via cloudrun-ship.
image = "ghcr.io/antinvestor/service-profile:v1.54.9"

# Public edge (docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname = "" # product surface: api.stawi.org/<path> only

# Profile accounts (variables.tf). Leave vault_addr empty until Vault is
# reachable from Cloud Run, the GCP auth role exists and the creation-code
# secret has a version. Then fill all of these from deployments/14601.json
# (stawilabs/stawi, testnet v4, executable 2026-10-14):
# vault_addr                       = "https://<vault host reachable from Cloud Run>"
# stawi_identity_key_version       = "1"
# stawi_account_factory            = "<.account.factory>"
# stawi_account_creation_code_hash = "<.account.creation_code_hash>"
# stawi_account_version            = "1"
