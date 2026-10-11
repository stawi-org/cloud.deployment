# Bootstrap pin (public GHCR). Routine rolls via cloudrun-ship.
image = "ghcr.io/antinvestor/service-profile:v1.54.9"

# Public edge (docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname = "" # product surface: api.stawi.org/<path> only

# Profile accounts (variables.tf). Leave accounts_enabled false until the
# identity-profile-accounts-salt and creation-code secrets have versions. Then
# fill these, the chain values from deployments/14601.json (stawilabs/stawi,
# testnet v4, executable 2026-10-14):
# accounts_enabled                 = true
# accounts_salt_version            = "1"
# stawi_account_factory            = "<.account.factory>"
# stawi_account_creation_code_hash = "<.account.creation_code_hash>"
# stawi_account_version            = "1"
