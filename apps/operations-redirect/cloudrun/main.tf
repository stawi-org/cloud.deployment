# operations-redirect — Frame Cloud Run via modules/frame-cloudrun-app.
# See generated_secrets.tf (service-files-encryption).

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Analytics may be staged on identity during ops project bootstrap (k8s → SM sync).
# Prefer TF_VAR; else copy from identity so Cloud Run always has a version to mount.
data "google_secret_manager_secret_version" "analytics_username" {
  count   = var.analytics_username == "" ? 1 : 0
  project = var.identity_project_id
  secret  = "${var.app_name}-analytics-username"
  version = "latest"
}

data "google_secret_manager_secret_version" "analytics_password" {
  count   = var.analytics_password == "" ? 1 : 0
  project = var.identity_project_id
  secret  = "${var.app_name}-analytics-password"
  version = "latest"
}

locals {
  # Sensitive values OK in secret_values; never use them in extra_version_ids keys.
  analytics_username_value = (
    var.analytics_username != ""
    ? var.analytics_username
    : data.google_secret_manager_secret_version.analytics_username[0].secret_data
  )
  analytics_password_value = (
    var.analytics_password != ""
    ? var.analytics_password
    : data.google_secret_manager_secret_version.analytics_password[0].secret_data
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

  # Encryption + analytics always versioned (values from random / TF_VAR / identity SM).
  extra_secret_ids = toset(concat(
    tolist(local.generated_secret_ids),
    [
      "${var.app_name}-analytics-username",
      "${var.app_name}-analytics-password",
    ],
  ))
  extra_version_ids = toset(concat(
    tolist(local.generated_secret_ids),
    [
      "${var.app_name}-analytics-username",
      "${var.app_name}-analytics-password",
    ],
  ))
  extra_secret_values = merge(
    local.generated_secret_values,
    {
      "${var.app_name}-analytics-username" = local.analytics_username_value
      "${var.app_name}-analytics-password" = local.analytics_password_value
    },
  )
  secret_env_extra = {
    ENCRYPTION_PHRASE  = { secret = "service-files-encryption" }
    ANALYTICS_USERNAME = { secret = "${var.app_name}-analytics-username" }
    ANALYTICS_PASSWORD = { secret = "${var.app_name}-analytics-password" }
  }

  app_env = {
    JOBS_BASE_URL      = "https://jobs.stawi.org/"
    ANALYTICS_BASE_URL = var.analytics_base_url
    # Colony in-cluster webhook; empty until product-opportunities is on Cloud Run.
    LINK_EXPIRED_WEBHOOKS = var.link_expired_webhooks
  }
}
