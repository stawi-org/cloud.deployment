# communications-ussd — the service-notification USSD engine (apps/ussd) on
# Cloud Run via modules/frame-cloudrun-app.
#
# Telco gateways (Africa's Talking) post sessions to /ussd/gateway/{service};
# each service is protected by its own auth_key, never by JWT. The management
# API (/api/v1/...) admits internal service accounts only (Seed registers its
# menu and pushes borrower state there). Completed sessions go to the
# notification service as inbound "ussd" notifications.

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
  container_port  = var.container_port
  memory          = var.memory
  migrate_args    = var.migrate_args
  # The setup job (migrate) is executed by ops, not on every apply.
  migrate_execute          = false
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-notification-ussd"

  app_env = {
    PROFILE_SERVICE_URI      = "https://api.stawi.org/profile"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    TENANCY_SERVICE_URI      = "https://api.stawi.org/tenancy"
  }
}
