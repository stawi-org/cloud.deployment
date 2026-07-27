# operations-thesa — Frame Cloud Run via modules/frame-cloudrun-app.

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

  # Analytics secret IDs always declared (seed via sync-cluster-secrets-to-gcp.sh).
  # Optional TF_VAR bootstrap; values never in git.
  extra_secret_ids = toset([
    "${var.app_name}-analytics-backend-url",
    "${var.app_name}-analytics-token",
  ])
  extra_secret_values = merge(
    var.analytics_backend_url != "" ? { "${var.app_name}-analytics-backend-url" = var.analytics_backend_url } : {},
    var.analytics_token != "" ? { "${var.app_name}-analytics-token" = var.analytics_token } : {},
  )
  secret_env_extra = {
    ANALYTICS_BACKEND_URL = { secret = "${var.app_name}-analytics-backend-url" }
    ANALYTICS_TOKEN       = { secret = "${var.app_name}-analytics-token" }
  }

  app_env = {
    ANALYTICS_BACKEND_TYPE = "uptrace"
  }
}
