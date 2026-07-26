# identity-tenancy — Frame Cloud Run via modules/frame-cloudrun-app.
# Extra: partition sync job (not part of the shared frame stack).
#
# Canonical public DNS: tenancy.stawi.org (edge-lb-identity + public-edge.yaml).
# Sync / internal callers must use that host (not *.run.app) so OIDC audience and
# product routing stay stable.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  # Prefer explicit public_hostname (tfvars / registry); fallback run.app only when unset.
  tenancy_public_host = trimspace(var.public_hostname) != "" ? trimspace(var.public_hostname) : ""
  tenancy_public_url  = local.tenancy_public_host != "" ? "https://${local.tenancy_public_host}" : ""
  # Sync endpoint path (same as K8s CronJob synchronize-partitions).
  sync_clients_path = "/_internal/sync/clients"
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

  # Accept Google ID tokens minted for https://tenancy.stawi.org (edge LB).
  custom_audiences = local.tenancy_public_url != "" ? [local.tenancy_public_url] : []

  app_env = merge(
    {
      SYNCHRONISE_PRIMARY_PARTITIONS = "true"
    },
    local.tenancy_public_url != "" ? {
      # Stable public base (edge DNS) for any in-process URL construction.
      PUBLIC_BASE_URL = local.tenancy_public_url
    } : {},
  )
}

locals {
  # Invoke via DNS when configured; else Cloud Run URL.
  sync_invoke_base = local.tenancy_public_url != "" ? local.tenancy_public_url : module.frame.service_uri
  sync_invoke_url  = "${local.sync_invoke_base}${local.sync_clients_path}"
  # OIDC audience must match custom_audiences (DNS) or the run.app service URL.
  sync_oidc_audience = local.tenancy_public_url != "" ? local.tenancy_public_url : module.frame.service_uri
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
    local.sync_invoke_url,
  ]
  execute    = false
  depends_on = [module.frame]
}

# Hourly schedule — same cadence as K8s CronJob "0 * * * *".
# POST https://tenancy.stawi.org/_internal/sync/clients with OIDC (audience = DNS host).
module "sync_schedule" {
  source                     = "../../../modules/cloudrun-keep-warm"
  project_id                 = var.project_id
  name                       = "sync-partitions-${var.app_name}"
  uri                        = local.sync_invoke_url
  schedule                   = "0 * * * *"
  time_zone                  = "Etc/UTC"
  http_method                = "POST"
  attempt_deadline           = "600s"
  scheduler_region           = "europe-west1"
  oidc_service_account_email = module.frame.runtime_service_account_email
  oidc_audience              = local.sync_oidc_audience
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
