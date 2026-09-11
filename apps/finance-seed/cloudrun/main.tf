# finance-seed — Frame Cloud Run (fintech seed direct-to-client lending).
# Composes identity, loans and operations behind RequestLoan + credit tiers.
# The setup job migrates schema, provisions the default credit ladder and
# registers the permission manifest.
# OAUTH2_SIGNER_API_KEY uses SM secret hydra-webhook-psk (historical name; remote JWT signer, not Hydra admin).

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  peer_env = {
    IDENTITY_SERVICE_URI   = "https://api.stawi.org/identity"
    LOAN_MGMT_SERVICE_URI  = "https://api.stawi.org/loans"
    OPERATIONS_SERVICE_URI = "https://api.stawi.org/operations"
    TENANCY_SERVICE_URI    = "https://api.stawi.org/tenancy"
    AUDIT_SERVICE_URI      = "https://api.stawi.org/audit"
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
  oauth2_service_client_id = "service-seed"

  grant_oauth_signer_accessor = true
  permissions_registration    = true
  startup_probe_path          = "/readyz"
  liveness_probe_path         = "/livez"

  app_env = merge(local.peer_env, {
    SECURELY_RUN_SERVICE = "true"
    SEED_CURRENCY_CODE   = "KES"
    LOG_FORMAT           = "json"
  })
  migrate_env = merge(local.peer_env, { LOG_FORMAT = "json" })
}
