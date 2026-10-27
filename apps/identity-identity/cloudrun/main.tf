# identity-identity — Frame Cloud Run via modules/frame-cloudrun-app.

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
  # Product APIs only on the path gateway.
  profile_uri      = "${local.api_base}/profile"
  tenancy_uri      = "${local.api_base}/tenancy"
  notification_uri = "${local.api_base}/notification"
  audit_uri        = "${local.api_base}/audit"
  files_uri        = "${local.api_base}/files"
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

  resource_path            = "/identity"
  requested_audience_paths = ["/profile", "/tenancy", "/notification", "/audit", "/files"]
  enable_keto_admin        = false

  app_env = merge({
    PREFER_SIMPLE_PROTOCOL                        = "true"
    MAX_AGENT_DEPTH                               = "5"
    PROFILE_SERVICE_URI                           = local.profile_uri
    TENANCY_SERVICE_URI                           = local.tenancy_uri
    NOTIFICATION_SERVICE_URI                      = local.notification_uri
    AUDIT_SERVICE_URI                             = local.audit_uri
    FILES_SERVICE_URI                             = local.files_uri
    OAUTH_REDIRECT_URIS                           = local.is_prod ? "https://app.antinvestor.com/auth/callback" : "https://app-dev.antinvestor.com/auth/callback"
    PROFILE_SERVICE_WORKLOAD_API_TARGET_PATH      = "/ns/profile/sa/service-profile"
    TENANCY_SERVICE_WORKLOAD_API_TARGET_PATH      = "/ns/auth/sa/service-tenancy"
    NOTIFICATION_SERVICE_WORKLOAD_API_TARGET_PATH = "/ns/notifications/sa/service-notification"
  }, module.runtime_db.service_env)
  # The setup Job registers the client and workforce message templates with
  # the notification service; it does not inherit app_env.
  migrate_env = merge({
    NOTIFICATION_SERVICE_URI = local.notification_uri
  }, module.runtime_db.migrate_env)
  migrate_secret_env_extra = module.runtime_db.migrate_secret_env
  secret_env_extra         = module.runtime_db.service_secret_env
}

# Row-level security applies to the role the service connects as; the setup
# Job keeps it (fintech pkg/dbrole). See modules/runtime-db-role.
module "runtime_db" {
  source = "../../../modules/runtime-db-role"

  app_name                      = var.app_name
  project_id                    = var.project_id
  labels                        = var.labels
  role                          = "identity_identity_rt"
  runtime_service_account_email = module.frame.runtime_service_account_email
  pooled_secret_id              = module.frame.database_secret_id
  direct_secret_id              = module.frame.database_direct_secret_id
  active                        = true
}
