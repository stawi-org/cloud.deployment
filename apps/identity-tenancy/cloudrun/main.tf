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

# Cluster CronJob parity (deployment.manifests synchronize-partitions):
# hourly POST /_internal/sync/clients — bulk repair Hydra clients, SA policies,
# partitions, and Keto accesses. Manual Cloud Run Job kept for operators.
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
    # Prefer Cloud Run URL so OIDC invoker works without relying on public edge.
    "${module.frame.service_uri}/_internal/sync/clients",
  ]
  execute    = false
  depends_on = [module.frame]
}

# Hourly schedule — same cadence as K8s CronJob "0 * * * *".
# OIDC as tenancy runtime SA (run.invoker already holds for self / public service).
module "sync_schedule" {
  source                     = "../../../modules/cloudrun-keep-warm"
  project_id                 = var.project_id
  name                       = "sync-partitions-${var.app_name}"
  uri                        = "${module.frame.service_uri}/_internal/sync/clients"
  schedule                   = "0 * * * *"
  time_zone                  = "Etc/UTC"
  http_method                = "POST"
  attempt_deadline           = "600s"
  scheduler_region           = "europe-west1"
  oidc_service_account_email = module.frame.runtime_service_account_email
  oidc_audience              = module.frame.service_uri
  depends_on                 = [module.frame]
}

# Scheduler agent must mint tokens as the tenancy runtime SA.
data "google_project" "this" {
  project_id = var.project_id
}

resource "google_service_account_iam_member" "scheduler_token_creator" {
  service_account_id = module.frame.runtime_service_account_name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}
