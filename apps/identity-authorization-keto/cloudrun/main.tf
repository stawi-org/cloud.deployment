# Ory Keto on Cloud Run + Neon + Pub/Sub.
# Migrations: Cloud Run Job runs `keto migrate up -y` before serve.

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "edge" {
  source = "../../../modules/edge-contract"
  env    = var.platform
}

module "db" {
  source    = "../../../modules/neon-database"
  app_name  = var.app_name
  org_id    = var.neon_org_id
  region_id = var.neon_region_id
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = substr(replace(var.app_name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.app_name}"
}

locals {
  database_secret_id        = "${var.app_name}-database-url"
  database_direct_secret_id = "${var.app_name}-database-url-direct"
  secret_ids = setunion(
    toset([local.database_secret_id, local.database_direct_secret_id]),
    var.extra_secret_ids,
  )
  version_ids = toset([local.database_secret_id, local.database_direct_secret_id])
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    { (local.database_direct_secret_id) = module.db.connection_uri },
    var.extra_secret_values,
  )
}

module "secrets" {
  source = "../../../modules/app-secrets"

  project_id = var.project_id
  labels     = var.labels

  secret_ids    = local.secret_ids
  version_ids   = local.version_ids
  secret_values = local.secret_values

  accessor_members = [
    "serviceAccount:${google_service_account.runtime.email}",
  ]
}

module "messaging" {
  source                        = "../../../modules/pubsub"
  project_id                    = var.project_id
  app_name                      = var.app_name
  runtime_service_account_email = google_service_account.runtime.email
  labels                        = var.labels
}

module "migrate" {
  source = "../../../modules/cloudrun-migrate-job"

  name                  = "${var.app_name}-migrate"
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  service_account_email = google_service_account.runtime.email
  labels                = var.labels
  # keto entrypoint is already "keto"
  args = ["migrate", "up", "-y"]
  env = {
    LOG_LEVEL = "info"
  }
  secret_env = {
    DSN = {
      secret = module.secrets.secret_ids[local.database_direct_secret_id]
    }
    DATABASE_URL = {
      secret = module.secrets.secret_ids[local.database_direct_secret_id]
    }
  }

  depends_on = [module.secrets]
}

module "service" {
  source                = "../../../modules/cloudrun-service"
  name                  = var.app_name
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  labels                = var.labels
  service_account_email = google_service_account.runtime.email
  # Keto read API default port
  container_port = 4466
  args           = ["serve", "read"]
  env = merge(
    module.edge.service_env,
    module.messaging.service_env,
    {
      GCP_PROJECT = var.project_id
      APP_NAME    = var.app_name
      LOG_LEVEL   = "info"
    },
  )
  secret_env = {
    DATABASE_URL = {
      secret = module.secrets.secret_ids[local.database_secret_id]
    }
    DSN = {
      secret = module.secrets.secret_ids[local.database_secret_id]
    }
  }

  depends_on = [
    module.secrets,
    module.messaging,
    module.migrate,
  ]
}
