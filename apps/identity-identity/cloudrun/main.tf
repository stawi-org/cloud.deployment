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
  requested_audience_paths = ["/profile", "/tenancy", "/notification"]
  enable_keto_admin        = false

  app_env = {
    PREFER_SIMPLE_PROTOCOL                        = "true"
    MAX_AGENT_DEPTH                               = "5"
    PROFILE_SERVICE_URI                           = local.profile_uri
    TENANCY_SERVICE_URI                           = local.tenancy_uri
    NOTIFICATION_SERVICE_URI                      = local.notification_uri
    PROFILE_SERVICE_WORKLOAD_API_TARGET_PATH      = "/ns/profile/sa/service-profile"
    TENANCY_SERVICE_WORKLOAD_API_TARGET_PATH      = "/ns/auth/sa/service-tenancy"
    NOTIFICATION_SERVICE_WORKLOAD_API_TARGET_PATH = "/ns/notifications/sa/service-notification"
  }
}
