# finance-funding — Frame Cloud Run (fintech funding).
# hydra-webhook-psk must be seeded OOB into stawi-finance (copy of identity).

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
  migrate_args             = var.migrate_args
  migrate_execute          = true  # first-cutover setup plan
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-funding"

  grant_oauth_signer_accessor = true
  permissions_registration    = true

  app_env = {
    PROFILE_SERVICE_URI      = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI      = "https://api.stawi.org/tenancy"
    LEDGER_SERVICE_URI       = "https://api.stawi.org/ledger"
    PAYMENT_SERVICE_URI      = "https://api.stawi.org/payment"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    SECURELY_RUN_SERVICE     = "true"
  }
}
