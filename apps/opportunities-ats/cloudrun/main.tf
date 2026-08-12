# opportunities-ats — employer ATS (service_ats).
# Own Neon on the opportunities org. Scheduling is platform-calendar only.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  matching_db_secret = "opportunities-matching-database-url"
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

  neon_org_id    = var.neon_org_id
  neon_region_id = var.neon_region_id

  resource_path = "/ats"
  requested_audience_paths = [
    "/profile",
    "/tenancy",
    "/calendar",
    "/notification",
  ]
  # Must own namespace service_ats (client_id with - → _).
  oauth2_service_client_id = "service-ats"

  migrate_args = ["setup"]
  migrate_env = {
    MIGRATION_PATH    = "/migrations/0001"
    ATS_MIGRATION_PATH = "/migrations/0001"
  }

  use_http2                = true
  permissions_registration = true
  exposure                 = "public"
  startup_probe_path       = "/readyz"
  liveness_probe_path      = "/livez"
  memory                   = "1Gi"
  cpu                      = "1"

  secret_env_extra = {
    # Optional talent shortlist (empty-safe if tables absent).
    ATS_MATCHING_DATABASE_URL = { secret = local.matching_db_secret }
  }

  app_env = {
    SECURELY_RUN_SERVICE   = "true"
    SERVER_PORT            = ":8080"
    AUTH_REQUIRE_JWT       = "true"
    CALENDAR_SERVICE_URI   = "https://api.stawi.org/calendar"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    PUBLIC_SITE_URL        = "https://opportunities.stawi.org"
  }
}

resource "google_secret_manager_secret_iam_member" "matching_db" {
  project   = var.project_id
  secret_id = local.matching_db_secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.frame.runtime_service_account_email}"
}
