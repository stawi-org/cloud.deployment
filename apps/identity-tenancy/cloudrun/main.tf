# identity-tenancy — Frame Cloud Run via modules/frame-cloudrun-app.
# Extra: partition sync job (not part of the shared frame stack).

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

  identity_project_id = null
  identity_region     = null

  neon_org_id    = var.neon_org_id
  neon_region_id = var.neon_region_id

  resource_path            = "/tenancy"
  requested_audience_paths = ["/profile", "/identity"]
  enable_keto_admin        = true
  migrate_execute          = false

  app_env = {
    SYNCHRONISE_PRIMARY_PARTITIONS = "true"
  }
}

# Cluster CronJob parity: job definition only (not executed every apply).
module "sync_job" {
  source                = "../../../modules/cloudrun-migrate-job"
  name                  = "${var.app_name}-sync-partitions"
  project_id            = var.project_id
  region                = var.region
  image                 = "curlimages/curl:8.20.0"
  service_account_email = module.frame.runtime_service_account_email
  labels                = var.labels
  args = [
    "-sS", "-X", "POST",
    "--retry", "8", "--retry-all-errors",
    "-o", "/dev/null", "-w", "%%{http_code}",
    "${module.frame.api_base}/tenancy/_internal/sync/clients",
  ]
  execute    = false
  depends_on = [module.frame]
}
