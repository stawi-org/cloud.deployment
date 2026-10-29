# platform-procurement — Frame Cloud Run via modules/frame-cloudrun-app.
# Pushes received resale stock to commerce and raw materials to manufacturing
# inventory, reads production plan shortages from manufacturing, and has
# trustage retry stock delivery on a schedule.

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
  # (tenancy migration 20260906_02_service_procurement.sql).
  oauth2_service_client_id = "service-procurement"

  # The setup Job registers the stock delivery retry workflow in trustage,
  # which calls back into PROCUREMENT_SERVICE_URI; it does not inherit app_env.
  migrate_env = merge({
    TRUSTAGE_SERVICE_URI    = "https://api.stawi.org/trustage"
    PROCUREMENT_SERVICE_URI = "https://api.stawi.org/procurement"
  }, module.runtime_db.migrate_env)
  migrate_secret_env_extra = module.runtime_db.migrate_secret_env
  secret_env_extra         = module.runtime_db.service_secret_env

  app_env = merge({
    COMMERCE_SERVICE_URI      = "https://api.stawi.org/commerce"
    MANUFACTURING_SERVICE_URI = "https://api.stawi.org/manufacturing"
    SECURELY_RUN_SERVICE      = "true"
    PROFILER_ENABLE           = "false"
  }, module.runtime_db.service_env)
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
  role                          = "platform_procurement_rt"
  runtime_service_account_email = module.frame.runtime_service_account_email
  pooled_secret_id              = module.frame.database_secret_id
  direct_secret_id              = module.frame.database_direct_secret_id
  active                        = false
}
