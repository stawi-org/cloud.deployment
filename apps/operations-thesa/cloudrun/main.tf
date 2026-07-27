# operations-thesa — Frame Cloud Run via modules/frame-cloudrun-app.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Prefer TF_VAR; else copy analytics staged on identity (k8s → SM bootstrap path).
data "google_secret_manager_secret_version" "analytics_backend_url" {
  count   = var.analytics_backend_url == "" ? 1 : 0
  project = var.identity_project_id
  secret  = "${var.app_name}-analytics-backend-url"
  version = "latest"
}

data "google_secret_manager_secret_version" "analytics_token" {
  count   = var.analytics_token == "" ? 1 : 0
  project = var.identity_project_id
  secret  = "${var.app_name}-analytics-token"
  version = "latest"
}

locals {
  analytics_backend_url_value = (
    var.analytics_backend_url != ""
    ? var.analytics_backend_url
    : data.google_secret_manager_secret_version.analytics_backend_url[0].secret_data
  )
  analytics_token_value = (
    var.analytics_token != ""
    ? var.analytics_token
    : data.google_secret_manager_secret_version.analytics_token[0].secret_data
  )
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

  # Analytics always versioned (TF_VAR or identity SM copy). Never commit values.
  extra_secret_ids = toset([
    "${var.app_name}-analytics-backend-url",
    "${var.app_name}-analytics-token",
  ])
  extra_version_ids = toset([
    "${var.app_name}-analytics-backend-url",
    "${var.app_name}-analytics-token",
  ])
  extra_secret_values = {
    "${var.app_name}-analytics-backend-url" = local.analytics_backend_url_value
    "${var.app_name}-analytics-token"       = local.analytics_token_value
  }
  secret_env_extra = {
    ANALYTICS_BACKEND_URL = { secret = "${var.app_name}-analytics-backend-url" }
    ANALYTICS_TOKEN       = { secret = "${var.app_name}-analytics-token" }
  }

  app_env = {
    ANALYTICS_BACKEND_TYPE = "uptrace"
  }
}
