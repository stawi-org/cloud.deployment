# platform-commerce — Frame Cloud Run via modules/frame-cloudrun-app.
# Multi-shop commerce: calls checkout, ledger, notification and trustage over
# the path gateway; trustage calls back for scheduled runs.

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
  migrate_env = local.peer_env

  app_env = merge(local.peer_env, {
    CHECKOUT_RETURN_URL  = var.checkout_return_url
    ORDER_PAYMENT_WINDOW = "45m"
    LEDGER_TIMEZONE      = "Africa/Nairobi"
    LEDGER_BOOK_TYPE     = "merchant"
    SECURELY_RUN_SERVICE = "true"
    PROFILER_ENABLE      = "false"
  })
}
