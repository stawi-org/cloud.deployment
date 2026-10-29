# platform-commerce — Frame Cloud Run via modules/frame-cloudrun-app.
# Multi-shop commerce: calls checkout, payment, ledger, notification, profile
# and trustage over the path gateway; trustage calls back for scheduled runs.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  # Peers reached over the path gateway; shared by the service and its setup job.
  peer_env = {
    CHECKOUT_SERVICE_URI     = "https://api.stawi.org/checkout"
    LEDGER_SERVICE_URI       = "https://api.stawi.org/ledger"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    TRUSTAGE_SERVICE_URI     = "https://api.stawi.org/trustage"
    COMMERCE_SERVICE_URI     = "https://api.stawi.org/commerce"
    WORKFLOWS_PATH           = "/workflows"
  }
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

  neon_org_id     = var.neon_org_id
  neon_region_id  = var.neon_region_id
  neon_extensions = var.neon_extensions
  has_database    = var.has_database

  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  container_port           = var.container_port
  memory                   = var.memory
  migrate_args             = var.migrate_args

  # Hydra client_id of the service account seeded in service-authentication
  # (tenancy migration 20260906_01_service_commerce.sql).
  oauth2_service_client_id = "service-commerce"

  # The setup job registers notification templates and trustage workflows,
  # so it needs the same peer URIs as the runtime (migrate_env is the only
  # env the module forwards to the job).
  migrate_env              = merge(local.peer_env, module.runtime_db.migrate_env)
  migrate_secret_env_extra = module.runtime_db.migrate_secret_env

  # WEBHOOK_SECRET_KEY seals shop webhook secrets at rest (base64 of 32 random
  # bytes); the service refuses to start without it. The secret is seeded out
  # of band: rotating it makes every shop set its webhook secret again.
  secret_env_extra = merge({
    WEBHOOK_SECRET_KEY = { secret = google_secret_manager_secret_iam_member.webhook_secret_key.secret_id }
  }, module.runtime_db.service_secret_env)

  app_env = merge(local.peer_env, {
    # Refunds are paid out through payment; the storefront finds or creates
    # guest buyers' profiles. The service refuses to start without either.
    PAYMENT_SERVICE_URI  = "https://api.stawi.org/payment"
    PROFILE_SERVICE_URI  = "https://api.stawi.org/profile"
    CHECKOUT_RETURN_URL  = var.checkout_return_url
    ORDER_PAYMENT_WINDOW = "45m"
    LEDGER_TIMEZONE      = "Africa/Nairobi"
    LEDGER_BOOK_TYPE     = "merchant"
    SECURELY_RUN_SERVICE = "true"
    PROFILER_ENABLE      = "false"
  }, module.runtime_db.service_env)
}

resource "google_secret_manager_secret_iam_member" "webhook_secret_key" {
  project   = var.project_id
  secret_id = "platform-commerce-webhook-secret-key"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.frame.runtime_service_account_email}"
}

# Row-level security applies to the role the service connects as; the setup
# Job keeps it (service-commerce pkg/dbrole). See modules/runtime-db-role.
# Leave active = false until a setup Job of a release with pkg/dbrole has
# created the role; then set it to true so the service connects as the role
# with DATABASE_REQUIRE_RLS=true.
module "runtime_db" {
  source = "../../../modules/runtime-db-role"

  app_name                      = var.app_name
  project_id                    = var.project_id
  labels                        = var.labels
  role                          = "platform_commerce_rt"
  runtime_service_account_email = module.frame.runtime_service_account_email
  pooled_secret_id              = module.frame.database_secret_id
  direct_secret_id              = module.frame.database_direct_secret_id
  active                        = false
}
