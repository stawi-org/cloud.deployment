# identity-tenancy — Frame Cloud Run via modules/frame-cloudrun-app.
# Extra: partition sync job (not part of the shared frame stack).
#
# Exposure: authenticated (no allUsers) — same model as Keto / Hydra admin.
# Public path: https://api.stawi.org/tenancy only (no tenancy.stawi.org host).
# Callers need run.invoker + Google ID token (audience = path gateway URL or run.app).
# Sync scheduler uses OIDC as the tenancy runtime SA.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  is_prod = var.platform == "stawi-prod"
  api_base = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"
  # Canonical public surface is the path gateway (override via public_hostname only if needed).
  tenancy_public_url = (
    trimspace(var.public_hostname) != ""
    ? (startswith(trimspace(var.public_hostname), "http")
      ? trimspace(var.public_hostname)
      : "https://${trimspace(var.public_hostname)}")
    : "${local.api_base}/tenancy"
  )
  # Sync endpoint path (same as K8s CronJob synchronize-partitions).
  sync_clients_path = "/_internal/sync/clients"

  # Callers allowed to invoke IAM-authenticated tenancy (identity + ops + platform).
  # Mirrors keto additional_invoker_members + identity runtimes + self (scheduler OIDC).
  identity_runtime_account_ids = toset([
    "identity-authentication",
    "identity-identity",
    "identity-profile",
    "identity-tenancy",
    "identity-oauth2-hydra",
  ])
  tenancy_invoker_members = setunion(
    toset([
      for id in local.identity_runtime_account_ids :
      "serviceAccount:${id}@${var.project_id}.iam.gserviceaccount.com"
    ]),
    var.additional_invoker_members,
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

  identity_project_id = null
  identity_region     = null

  neon_org_id    = var.neon_org_id
  neon_region_id = var.neon_region_id

  resource_path            = "/tenancy"
  requested_audience_paths = ["/profile", "/identity"]
  enable_keto_admin        = true
  migrate_execute          = false

  # Control plane: IAM required (no allUsers). Public path = api.stawi.org/tenancy.
  exposure         = "authenticated"
  public_invoker   = false
  invoker_members  = local.tenancy_invoker_members
  # Frame dual-auth mints Google ID tokens with audience = https://host only
  # (no path). Accept both the path-gateway URL and the api host so S2S via
  # TENANCY_SERVICE_URI=https://api.stawi.org/tenancy works (X-Serverless-Authorization).
  custom_audiences = distinct(concat(
    [local.tenancy_public_url],
    [local.api_base],
  ))

  app_env = {
    SYNCHRONISE_PRIMARY_PARTITIONS = "true"
    DATABASE_LOG_QUERIES           = "false"
    PROFILE_SERVICE_URI            = "${local.api_base}/profile"
    PUBLIC_BASE_URL                = local.tenancy_public_url
  }
  # Tenancy is the registration target — skip self-registration loop.
  permissions_registration = false
}

locals {
  # Prefer direct Cloud Run URL for scheduler (reliable IAM; no CF hop).
  # Audience still includes path-gateway URL via custom_audiences for other callers.
  sync_invoke_base   = module.frame.service_uri
  sync_invoke_url    = "${local.sync_invoke_base}${local.sync_clients_path}"
  sync_oidc_audience = module.frame.service_uri
}

# Cluster CronJob parity (deployment.manifests synchronize-partitions):
# hourly POST /_internal/sync/clients — bulk repair Hydra clients, SA policies,
# partitions, and Keto accesses. Manual Cloud Run Job kept for operators.
#
# Tenancy is exposure=authenticated: bare curl gets 403. Mint a Google ID token
# from the runtime SA metadata (audience = DNS or run.app) before POSTing.
module "sync_job" {
  source                = "../../../modules/cloudrun-migrate-job"
  name                  = "${var.app_name}-sync-partitions"
  project_id            = var.project_id
  region                = var.region
  image                 = "curlimages/curl:8.20.0"
  service_account_email = module.frame.runtime_service_account_email
  labels                = var.labels
  command               = ["sh", "-c"]
  args = [
    <<-EOT
    set -eu
    AUD='${local.sync_oidc_audience}'
    TOKEN=$(curl -sS -H 'Metadata-Flavor: Google' \
      "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=$${AUD}")
    CODE=$(curl -sS -X POST \
      -H "Authorization: Bearer $${TOKEN}" \
      --retry 8 --retry-all-errors \
      -o /dev/null -w "%%{http_code}" \
      '${local.sync_invoke_url}')
    echo "$${CODE}"
    case "$${CODE}" in 200|202|204) exit 0;; *) exit 1;; esac
    EOT
  ]
  execute    = false
  depends_on = [module.frame]
}

# Hourly schedule — same cadence as K8s CronJob "0 * * * *".
# POST Cloud Run URL /_internal/sync/clients with OIDC (audience = run.app URI).
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
