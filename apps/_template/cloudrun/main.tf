# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------
provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = local.platform.project_id
  region  = local.platform.region
}

# ---------------------------------------------------------------------------
# Platform selection (module sources must be constant strings in Terraform)
# CI passes -var=platform=stawi-dev|stawi-prod (or env tfvars).
# ---------------------------------------------------------------------------
module "platform_dev" {
  source = "../../../platforms/stawi-dev"
  count  = var.platform == "stawi-dev" ? 1 : 0
}

module "platform_prod" {
  source = "../../../platforms/stawi-prod"
  count  = var.platform == "stawi-prod" ? 1 : 0
}

locals {
  platform = var.platform == "stawi-dev" ? module.platform_dev[0] : module.platform_prod[0]
}

# ---------------------------------------------------------------------------
# Edge contract + Neon database
# ---------------------------------------------------------------------------
module "edge" {
  source = "../../../modules/edge-contract"
  env    = local.platform.env
}

module "db" {
  source    = "../../../modules/neon-database"
  app_name  = var.app_name
  region_id = var.neon_region_id
}

# ---------------------------------------------------------------------------
# DATABASE_URL in Secret Manager
# ---------------------------------------------------------------------------
resource "google_secret_manager_secret" "database_url" {
  project   = local.platform.project_id
  secret_id = "${var.app_name}-database-url"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = module.db.pooled_connection_uri
}

# Runtime SA owned by the app root so secret IAM can be granted before Cloud Run.
resource "google_service_account" "runtime" {
  project      = local.platform.project_id
  account_id   = substr(replace(var.app_name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.app_name}"
}

resource "google_secret_manager_secret_iam_member" "run_accessor" {
  project   = local.platform.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

# ---------------------------------------------------------------------------
# Cloud Run service
# ---------------------------------------------------------------------------
module "service" {
  source                = "../../../modules/cloudrun-service"
  name                  = var.app_name
  project_id            = local.platform.project_id
  region                = local.platform.region
  image                 = var.image
  labels                = local.platform.labels
  service_account_email = google_service_account.runtime.email
  env                   = module.edge.service_env
  secret_env = {
    DATABASE_URL = {
      secret = google_secret_manager_secret.database_url.secret_id
    }
  }

  depends_on = [
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_iam_member.run_accessor,
  ]
}
