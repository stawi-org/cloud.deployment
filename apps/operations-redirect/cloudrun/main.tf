# operations-redirect — Frame Cloud Run via modules/frame-cloudrun-app.
# See generated_secrets.tf (service-files-encryption).

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

  # Encryption phrase always mounted. Analytics secret IDs always declared so
  # scripts/sync-cluster-secrets-to-gcp.sh can seed values without TF_VAR;
  # optional bootstrap via TF_VAR still supported. Never commit values.
  extra_secret_ids = toset(concat(
    tolist(local.generated_secret_ids),
    [
      "${var.app_name}-analytics-username",
      "${var.app_name}-analytics-password",
    ],
  ))
  extra_secret_values = merge(
    local.generated_secret_values,
    var.analytics_username != "" ? { "${var.app_name}-analytics-username" = var.analytics_username } : {},
    var.analytics_password != "" ? { "${var.app_name}-analytics-password" = var.analytics_password } : {},
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
