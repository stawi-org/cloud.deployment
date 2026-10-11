# identity-profile — Frame Cloud Run via modules/frame-cloudrun-app.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  is_prod  = var.platform == "stawi-prod"
  api_base = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"

  # Profile accounts (variables.tf). One switch: the identity key and the
  # account derivation must be configured together.
  accounts_enabled             = var.accounts_enabled
  accounts_salt_secret         = "identity-profile-accounts-salt"
  accounts_salt_dir            = "/var/run/secrets/stawi-identity"
  account_creation_code_secret = "identity-profile-stawi-account-creation-code"
  account_creation_code_dir    = "/var/run/secrets/stawi-account"
  accounts_env = local.accounts_enabled ? {
    ACCOUNTS_SALT_FILE               = "${local.accounts_salt_dir}/salt"
    STAWI_ACCOUNT_FACTORY            = var.stawi_account_factory
    STAWI_ACCOUNT_CREATION_CODE_FILE = "${local.account_creation_code_dir}/creation_code"
    STAWI_ACCOUNT_CREATION_CODE_HASH = var.stawi_account_creation_code_hash
    STAWI_ACCOUNT_VERSION            = var.stawi_account_version
  } : {}
}

check "profile_accounts_complete" {
  assert {
    condition = !local.accounts_enabled || alltrue([
      var.accounts_salt_version != "",
      var.stawi_account_factory != "",
      var.stawi_account_creation_code_hash != "",
      var.stawi_account_version != "",
    ])
    error_message = "accounts_enabled is true, so accounts_salt_version, stawi_account_factory, stawi_account_creation_code_hash and stawi_account_version are required (service-profile refuses to start on a half configuration)."
  }
}

module "frame" {
  source = "../../../modules/frame-cloudrun-app"

  app_name   = var.app_name
  project_id = var.project_id
  region     = var.region
  platform   = var.platform
  image      = var.image
  labels     = var.labels

  identity_project_id = null
  identity_region     = null

  neon_org_id    = var.neon_org_id
  neon_region_id = var.neon_region_id

  resource_path            = "/profile"
  requested_audience_paths = ["/notification", "/tenancy", "/devices"]
  enable_keto_admin        = false
  min_instance_count       = 1

  # DEK secret *containers* only — versions are seeded out-of-band from colony
  # (config.go defaults / vault stawi/identity/default/dek-keys). Do not put these
  # in extra_version_ids: tofu random keys previously overwrote the real DEK.
  extra_secret_ids = toset([
    "identity-profile-dek-key-id",
    "identity-profile-dek-aes-key",
    "identity-profile-dek-hmac-key",
    # Container only; seeded from the chain (variables.tf), not secret data.
    "identity-profile-stawi-account-creation-code",
    # Container only; K_identity, seeded once out-of-band (variables.tf).
    "identity-profile-accounts-salt",
  ])
  extra_version_ids   = toset([])
  extra_secret_values = {}
  secret_env_extra = {
    DEK_LOOKUP_TOKEN            = { secret = "identity-profile-dek-hmac-key" }
    DEK_ACTIVE_KEY_ID           = { secret = "identity-profile-dek-key-id" }
    DEK_ACTIVE_ENCRYPTION_TOKEN = { secret = "identity-profile-dek-aes-key" }
  }
  migrate_secret_env_extra = {
    DEK_LOOKUP_TOKEN            = { secret = "identity-profile-dek-hmac-key" }
    DEK_ACTIVE_KEY_ID           = { secret = "identity-profile-dek-key-id" }
    DEK_ACTIVE_ENCRYPTION_TOKEN = { secret = "identity-profile-dek-aes-key" }
  }

  # Service and setup job both get the accounts config: the setup job runs the
  # account-backfill step.
  secret_volumes = local.accounts_enabled ? {
    stawi-account = {
      secret     = local.account_creation_code_secret
      mount_path = local.account_creation_code_dir
      file_name  = "creation_code"
    }
    # Pinned: a different version of K_identity moves every address.
    stawi-identity = {
      secret     = local.accounts_salt_secret
      mount_path = local.accounts_salt_dir
      file_name  = "salt"
      version    = var.accounts_salt_version
    }
  } : {}
  migrate_env = local.accounts_env

  app_env = merge({
    TRACE_REQUESTS           = "false"
    DEK_OLD_ENCRYPTION_TOKEN = ""
    # Colony: service-notification.communications.svc — not yet on Cloud Run.
    NOTIFICATION_SERVICE_URI = "${local.api_base}/notification"
  }, local.accounts_env)
}
