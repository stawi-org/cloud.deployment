# finance-loans — Frame Cloud Run (fintech loans).
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
  # Matches Hydra client from cluster cluster release name service-loans.
  oauth2_service_client_id = "service-loans"

  grant_oauth_signer_accessor = true
  permissions_registration    = true
  startup_probe_path          = "/readyz"
  liveness_probe_path         = "/livez"

  app_env = {
    PROFILE_SERVICE_URI      = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI      = "https://api.stawi.org/tenancy"
    OPERATIONS_SERVICE_URI   = "https://api.stawi.org/operations"
    LEDGER_SERVICE_URI       = "https://api.stawi.org/ledger"
    PAYMENT_SERVICE_URI      = "https://api.stawi.org/payment"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    TRUSTAGE_SERVICE_URI     = "https://api.stawi.org/trustage"
    AUDIT_SERVICE_URI        = "https://api.stawi.org/audit"
    FIELD_SERVICE_URI        = "https://api.stawi.org/identity"
    FUNDING_SERVICE_URI      = "https://api.stawi.org/funding"
    IDENTITY_SERVICE_URI     = "https://api.stawi.org/identity"
    LIMITS_SERVICE_URI       = "https://api.stawi.org/limits"
    SEED_SERVICE_URI         = "https://api.stawi.org/seed"
    SECURELY_RUN_SERVICE     = "true"
  }
  # The setup Job registers the borrower message templates with the
  # notification service and the loans job schedules with trustage; it does
  # not inherit app_env.
  migrate_env = {
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    TRUSTAGE_SERVICE_URI     = "https://api.stawi.org/trustage"
  }
}
