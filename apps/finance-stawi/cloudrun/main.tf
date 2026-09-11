# finance-stawi — Frame Cloud Run (fintech stawi group-lending product).
# Composes identity, loans, savings, ledger, payment, notification, files,
# profile, tenancy and limits behind the product API. The setup job registers
# the permission manifest and syncs /workflows into trustage.
# OAUTH2_SIGNER_API_KEY uses SM secret hydra-webhook-psk (historical name; remote JWT signer, not Hydra admin).

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  # Needed by both the runtime service and the setup job (workflow sync +
  # permission registration go through these peers).
  peer_env = {
    IDENTITY_SERVICE_URI     = "https://api.stawi.org/identity"
    LOANMGMT_SERVICE_URI     = "https://api.stawi.org/loans"
    SAVINGS_SERVICE_URI      = "https://api.stawi.org/savings"
    LEDGER_SERVICE_URI       = "https://api.stawi.org/ledger"
    PAYMENT_SERVICE_URI      = "https://api.stawi.org/payment"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    FILES_SERVICE_URI        = "https://api.stawi.org/files"
    PROFILE_SERVICE_URI      = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI      = "https://api.stawi.org/tenancy"
    LIMITS_SERVICE_URI       = "https://api.stawi.org/limits"
    AUDIT_SERVICE_URI        = "https://api.stawi.org/audit"
    TRUSTAGE_SERVICE_URI     = "https://api.stawi.org/trustage"
    TRUSTAGE_URL             = "https://api.stawi.org/trustage"
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
  oauth2_service_client_id = "service-stawi"

  grant_oauth_signer_accessor = true
  permissions_registration    = true
  startup_probe_path          = "/readyz"
  liveness_probe_path         = "/livez"

  app_env = merge(local.peer_env, {
    SECURELY_RUN_SERVICE                       = "true"
    LIMITS_GATE_ENABLED_STAWI_LOAN_DISBURSEMENT = "true"
    LIMITS_GATE_MODE_STAWI_LOAN_DISBURSEMENT    = "enforce"
    LOG_FORMAT                                 = "json"
  })
  # v1.96.27 binaries still use the legacy DO_MIGRATION gate for the setup
  # path (ShouldRunSetup lands in the next release); keep both until then.
  migrate_env = merge(local.peer_env, { LOG_FORMAT = "json", DO_MIGRATION = "true" })
}
