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

  app_env = {
    TRACE_REQUESTS           = "false"
    DEK_OLD_ENCRYPTION_TOKEN = ""
    # Colony: service-notification.communications.svc — not yet on Cloud Run.
    NOTIFICATION_SERVICE_URI = "${local.api_base}/notification"
  }
}
