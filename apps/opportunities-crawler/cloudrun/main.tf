# opportunities-crawler — owns crawl Neon (separate from product/matching Neon).
# Long-running crawl remains on the cluster; this stack provisions DB + migrate.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {
  project_id = var.project_id
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
  has_database    = true

  container_port = var.container_port
  memory         = var.memory
  cpu            = "1"

  # Crawler binary migrates when DO_DATABASE_MIGRATE=true (not Frame "setup").
  migrate_args = []
  migrate_env = {
    DO_DATABASE_MIGRATE = "true"
    DO_SETUP            = "false"
    MIGRATION_PATH      = "/migrations/0001"
  }

  # No public product path — DB ownership + migrate only.
  resource_path            = ""
  requested_audience_paths = []
  oauth2_service_client_id = "opportunities-crawler"

  grant_oauth_signer_accessor = false
  enable_messaging            = false
  permissions_registration    = false
  use_http2                   = true
  exposure                    = "private"
  min_instance_count          = 0
  max_instance_count          = 1
  startup_probe_path          = "/healthz"
  liveness_probe_path         = "/healthz"

  app_env = {
    SECURELY_RUN_SERVICE = "true"
    SERVER_PORT          = ":8080"
    # Prefer not running crawl schedules on Cloud Run; cluster owns schedules.
    INTERNAL_OVERDUE_INTERVAL = "0"
  }
}
