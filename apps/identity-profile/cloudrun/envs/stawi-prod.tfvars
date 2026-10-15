# Bootstrap pin (public GHCR). Routine rolls via cloudrun-ship.
image = "ghcr.io/antinvestor/service-profile:v1.54.23"

# Public edge (docs/PUBLIC_EDGE_DNS.md + config/public-edge.yaml)
public_hostname = "" # product surface: api.stawi.org/<path> only

# Profile accounts (variables.tf). Leave accounts_enabled false until the
# identity-profile-accounts-salt and creation-code secrets have versions. Then
# uncomment these, the chain values from deployments/14601.json
# (stawilabs/stawi, testnet v6, executable 2026-10-18 09:17:45 UTC). The
# creation-code secret is seeded from CodeStore
# 0xE0CeA5b852a5bf9E2775b79CC3188C2C39d3e0eA (variables.tf):
# accounts_enabled                 = true
# accounts_salt_version            = "1"
# stawi_account_factory            = "0x5f3107cdE485eBc8De0d3158fE8e88e647E0eEA0"
# stawi_account_creation_code_hash = "0xddb93fc72110b8935673157f7bbd06f5f5205455f77361bbc3c7315bfd080689"
# stawi_account_version            = "1"
