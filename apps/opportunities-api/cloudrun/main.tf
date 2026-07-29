# opportunities-api — public discovery on Cloud Run.
# Does NOT create a Neon project; mounts opportunities-matching product DB secrets.
# Crawl admin disabled (SOURCE_ADMIN_ENABLED=false).

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  # Shared product DB owned by opportunities-matching (apply matching first).
  product_db_secret        = "opportunities-matching-database-url"
  product_db_direct_secret = "opportunities-matching-database-url-direct"
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
  neon_extensions          = []
  has_database             = false
  container_port           = var.container_port
  memory                   = var.memory
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  # Hydra internal client_id from service-authentication greenfield seed.
  oauth2_service_client_id = "opportunities-api"

  grant_oauth_signer_accessor = true
  # API uses net/http (not Frame h2c server).
  use_http2                   = false
  permissions_registration    = false
  enable_messaging            = false
  startup_probe_path          = "/healthz"
  liveness_probe_path         = "/healthz"

  secret_env_extra = {
    DATABASE_URL         = { secret = local.product_db_secret }
    REPLICA_DATABASE_URL = { secret = local.product_db_secret }
  }

  app_env = {
    SOURCE_ADMIN_ENABLED = "false"
    # Prefer lakebase_text after Lakebase Search + extension; plain is safe fallback.
    SEARCH_BACKEND       = "lakebase_text"
    PROFILE_SERVICE_URI  = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI  = "https://api.stawi.org/tenancy"
    SECURELY_RUN_SERVICE = "true"
    # net/http listen (frame module also sets SERVER_PORT; keep explicit).
    SERVER_PORT          = ":8080"
  }
}

# Product DB secrets are owned by opportunities-matching; grant this runtime access.
resource "google_secret_manager_secret_iam_member" "product_db" {
  for_each = toset([
    local.product_db_secret,
    local.product_db_direct_secret,
  ])
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.frame.runtime_service_account_email}"
}
