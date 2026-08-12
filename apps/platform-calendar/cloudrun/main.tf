# platform-calendar — shared resource booking plane (service_calendar).
# Source: github.com/stawi-opportunities/opportunities apps/calendar
# Lives on stawi-platform / platform Neon — not opportunities-*.

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

  neon_org_id    = var.neon_org_id
  neon_region_id = var.neon_region_id

  resource_path            = "/calendar"
  requested_audience_paths = ["/profile", "/tenancy"]
  # Derived as service-calendar from platform-* ; set explicitly for grep/docs.
  oauth2_service_client_id = "service-calendar"

  migrate_args = ["setup"]
  migrate_env = {
    MIGRATION_PATH          = "/migrations/0001"
    CALENDAR_MIGRATION_PATH = "/migrations/0001"
  }

  use_http2                = true
  permissions_registration = true
  exposure                 = "public"
  startup_probe_path       = "/readyz"
  liveness_probe_path      = "/livez"
  memory                   = "512Mi"
  cpu                      = "1"

  app_env = {
    SECURELY_RUN_SERVICE = "true"
    SERVER_PORT          = ":8080"
    AUTH_REQUIRE_JWT     = "true"
  }
}
