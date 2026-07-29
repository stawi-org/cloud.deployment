# finance-limits — Frame Cloud Run (fintech limits / policy engine).
# oauth2 client_id service-limits is seeded by service-authentication tenancy.
# OAUTH2_SIGNER_API_KEY uses SM secret hydra-webhook-psk (historical name; remote JWT signer, not Hydra admin).

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "frame" {
  source = "../../../modules/frame-cloudrun-app"

  app_name   = var.app_name
  project_id = var.project_id
  region     = var.region
  platform   = var.platform
  image      = var.image
  labels     = var.labels

  identity_project_id = var.identity_project_id
  identity_region     = var.identity_region

  neon_org_id              = var.neon_org_id
  neon_region_id           = var.neon_region_id
  neon_extensions          = var.neon_extensions
  has_database             = var.has_database
  container_port           = var.container_port
  memory                   = var.memory
  migrate_args             = ["setup", "migrate"]  # permissions step needs tenancy OAuth; register later
  migrate_execute          = false
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-limits"

  grant_oauth_signer_accessor = true
  permissions_registration    = false  # enable after service-bot can POST tenancy register

  app_env = {
    PROFILE_SERVICE_URI                 = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI                 = "https://api.stawi.org/tenancy"
    POLICY_CACHE_TTL_SECONDS            = "60"
    SUBJECT_ATTRIBUTE_CACHE_TTL_SECONDS = "60"
    SECURELY_RUN_SERVICE                = "true"
  }
}
