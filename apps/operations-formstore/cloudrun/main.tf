# operations-formstore — Frame Cloud Run via modules/frame-cloudrun-app.

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

  app_env = {
    MAX_SUBMISSION_SIZE   = "10485760"
    SUBMISSION_RATE_LIMIT = "100"
    # Colony: FILE_SERVICE_URL → service-files.platform.svc
    FILE_SERVICE_URL = (
      var.platform == "stawi-prod"
      ? "https://api.stawi.org/files"
      : "https://api.stawi.dev/files"
    )
    # No Valkey on Cloud Run yet — app should tolerate empty/mem if supported.
    # Leave unset rather than broken cluster DNS: VALKEY_CACHE_URL.
  }
}
