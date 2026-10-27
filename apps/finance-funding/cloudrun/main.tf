# finance-funding — Frame Cloud Run (fintech funding).
# OAUTH2_SIGNER_API_KEY uses SM secret hydra-webhook-psk (historical name; remote JWT signer, not Hydra admin).

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
  migrate_args             = ["setup"]
  migrate_execute          = false
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-funding"

  grant_oauth_signer_accessor = true
  permissions_registration    = true
  startup_probe_path          = "/readyz"
  liveness_probe_path         = "/livez"

  app_env = merge({
    PROFILE_SERVICE_URI      = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI      = "https://api.stawi.org/tenancy"
    LEDGER_SERVICE_URI       = "https://api.stawi.org/ledger"
    PAYMENT_SERVICE_URI      = "https://api.stawi.org/payment"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    AUDIT_SERVICE_URI        = "https://api.stawi.org/audit"
    IDENTITY_SERVICE_URI     = "https://api.stawi.org/identity"
    LIMITS_SERVICE_URI       = "https://api.stawi.org/limits"
    LOAN_MGMT_SERVICE_URI    = "https://api.stawi.org/loans"
    OPERATIONS_SERVICE_URI   = "https://api.stawi.org/operations"
    SAVINGS_SERVICE_URI      = "https://api.stawi.org/savings"
    SECURELY_RUN_SERVICE     = "true"
  }, module.runtime_db.service_env)
  migrate_env              = module.runtime_db.migrate_env
  migrate_secret_env_extra = module.runtime_db.migrate_secret_env
  secret_env_extra         = module.runtime_db.service_secret_env
}

# Row-level security applies to the role the service connects as; the setup
# Job keeps it (fintech pkg/dbrole). See modules/runtime-db-role.
module "runtime_db" {
  source = "../../../modules/runtime-db-role"

  app_name                      = var.app_name
  project_id                    = var.project_id
  labels                        = var.labels
  role                          = "finance_funding_rt"
  runtime_service_account_email = module.frame.runtime_service_account_email
  pooled_secret_id              = module.frame.database_secret_id
  direct_secret_id              = module.frame.database_direct_secret_id
  active                        = true
}
