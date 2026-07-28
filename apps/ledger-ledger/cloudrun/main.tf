# ledger-ledger — Frame Cloud Run via modules/frame-cloudrun-app.
# hydra-webhook-psk seeded OOB into stawi-ledger (copy of identity).

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
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-ledger"

  grant_oauth_signer_accessor = true

  app_env = {
    TENANCY_SERVICE_URI = "https://api.stawi.org/tenancy"
    PROFILE_SERVICE_URI = "https://api.stawi.org/profile"
  }
}
