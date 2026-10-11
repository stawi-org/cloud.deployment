variable "app_name" {
  type        = string
  description = "Application name (directory name; Cloud Run service + Neon project prefix)"
}

variable "image" {
  type        = string
  description = "Container image for Cloud Run"
}

variable "project_id" {
  type        = string
  description = "GCP project from gcp-accounts registry (resolved by CI)"
}

variable "region" {
  type        = string
  description = "GCP region from gcp-accounts registry"
  default     = "europe-west1"
}

variable "labels" {
  type        = map(string)
  description = "Resource labels from gcp-accounts registry"
  default     = {}
}

variable "platform" {
  type        = string
  description = "Deploy env name (stawi-dev | stawi-prod) for edge-contract"
}

variable "neon_region_id" {
  type    = string
  default = "aws-eu-central-1"
}

variable "neon_org_id" {
  type        = string
  description = "Neon organization id (from neon-accounts registry / SOPS); required for project create"
  default     = ""
}

variable "neon_api_key" {
  type        = string
  sensitive   = true
  description = "Neon org API key (from SOPS credentials via CI (SOPS_AGE_KEY) — never commit)"
}

variable "extra_secret_values" {
  type        = map(string)
  sensitive   = true
  default     = {}
  description = "Additional SM secrets (id → value) managed by tofu; prefer empty and out-of-band for human secrets"
}

variable "extra_secret_ids" {
  type        = set(string)
  default     = []
  description = "SM secret IDs to create without versions (fill versions outside git)"
}

variable "public_hostname" {
  type        = string
  default     = ""
  description = "Canonical public FQDN for this service (Cloud Run domain mapping)"
}


# ---------------------------------------------------------------------------
# Profile accounts (service-profile >= v1.55.0, docs/PROFILE_ACCOUNTS.md)
# ---------------------------------------------------------------------------
# Off while accounts_enabled is false: profiles are created without chain
# accounts (the service's development posture). Turning it on mounts
# K_identity and the creation code as files and sets the account env on the
# service and the setup job (backfill), so every value below must then be set —
# the service refuses to start on a half configuration or a missing, empty or
# short (< 32 bytes) key file.
#
# K_identity lives in the Secret Manager secret `identity-profile-accounts-salt`
# as 32 raw random bytes, mounted at ACCOUNTS_SALT_FILE. Seed it once, never
# add another version, and pin accounts_salt_version to the version created:
#   openssl rand 32 > k_identity.bin
#   gcloud secrets versions add identity-profile-accounts-salt \
#     --project=stawi-identity --data-file=k_identity.bin
#   shred -u k_identity.bin
#
# Chain values come from the Stawi testnet v4 deployment record
# `deployments/14601.json` in stawilabs/stawi (written by `make testnet` at
# execute time, 2026-10-14):
#   stawi_account_factory            = .account.factory
#   stawi_account_creation_code_hash = .account.creation_code_hash
#   stawi_account_version            = .account.account_version
# The creation code itself is too large for an env var (up to 24,575 bytes →
# ~49 KB hex). It is stored in the Secret Manager secret
# `identity-profile-stawi-account-creation-code` and mounted as a file
# (STAWI_ACCOUNT_CREATION_CODE_FILE). Seed it from the chain's CodeStore at
# `.code_stores.StawiAccount.address` (runtime code minus the leading 0x00):
#   cast code <code_store> --rpc-url <rpc> | sed 's/^0x00/0x/' \
#     | gcloud secrets versions add identity-profile-stawi-account-creation-code \
#         --project=stawi-identity --data-file=-
# The service checks keccak256(creation code) against
# stawi_account_creation_code_hash at startup.

variable "accounts_enabled" {
  type        = bool
  default     = false
  description = "Derive profile chain accounts: mounts K_identity (ACCOUNTS_SALT_FILE) and the creation code, and sets STAWI_ACCOUNT_*."
}

variable "accounts_salt_version" {
  type        = string
  default     = ""
  description = "Pinned Secret Manager version of identity-profile-accounts-salt (K_identity), e.g. \"1\". Never changed once accounts exist."

  validation {
    condition     = var.accounts_salt_version == "" || can(regex("^[1-9][0-9]*$", var.accounts_salt_version))
    error_message = "accounts_salt_version must be a numeric Secret Manager version (not \"latest\")."
  }
}

variable "stawi_account_factory" {
  type        = string
  default     = ""
  description = "Canonical AccountFactory address (STAWI_ACCOUNT_FACTORY) — deployments/14601.json .account.factory"

  validation {
    condition     = var.stawi_account_factory == "" || can(regex("^0x[0-9a-fA-F]{40}$", var.stawi_account_factory))
    error_message = "stawi_account_factory must be a 0x-prefixed 20-byte address."
  }
}

variable "stawi_account_creation_code_hash" {
  type        = string
  default     = ""
  description = "keccak256 of the StawiAccount creation code (STAWI_ACCOUNT_CREATION_CODE_HASH) — deployments/14601.json .account.creation_code_hash"

  validation {
    condition     = var.stawi_account_creation_code_hash == "" || can(regex("^0x[0-9a-fA-F]{64}$", var.stawi_account_creation_code_hash))
    error_message = "stawi_account_creation_code_hash must be a 0x-prefixed 32-byte hex digest."
  }
}

variable "stawi_account_version" {
  type        = string
  default     = "1"
  description = "Account version (STAWI_ACCOUNT_VERSION) — deployments/14601.json .account.account_version"
}
