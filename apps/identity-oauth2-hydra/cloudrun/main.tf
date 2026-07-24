# Ory Hydra on Cloud Run + Neon + Pub/Sub.
# Migrations: Cloud Run Job runs `hydra migrate sql -e --yes` before serve.

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
  app_secret_ids = toset([
    "identity-oauth2-hydra-secrets-system",
    "identity-oauth2-hydra-secrets-cookie",
    "hydra-webhook-psk",
  ])
  secret_ids = setunion(
    toset([local.database_secret_id, local.database_direct_secret_id]),
    local.app_secret_ids,
    var.extra_secret_ids,
  )
  version_ids = setunion(
    toset([local.database_secret_id, local.database_direct_secret_id]),
    local.app_secret_ids,
  )
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    { (local.database_direct_secret_id) = module.db.connection_uri },
    local.generated_secret_values,
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
  # hydra entrypoint is already "hydra"
  args = ["migrate", "sql", "-e", "--yes"]
  env = {
    LOG_LEVEL = "info"
  }
  secret_env = {
    # Hydra reads DSN from env with -e
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
  container_port        = 4444
  args                  = ["serve", "public"]
  env = merge(
    module.edge.service_env,
    module.messaging.service_env,
    {
      GCP_PROJECT                       = var.project_id
      APP_NAME                          = var.app_name
      SERVE_PUBLIC_PORT                 = "4444"
      SERVE_PUBLIC_CORS_ALLOWED_ORIGINS = "https://accounts.stawi.org"
      URLS_SELF_ISSUER                  = "https://oauth2.stawi.org"
      URLS_CONSENT                      = "https://accounts.stawi.org/consent"
      URLS_LOGIN                        = "https://accounts.stawi.org/login"
      URLS_LOGOUT                       = "https://accounts.stawi.org/logout"
      STRATEGIES_ACCESS_TOKEN           = "jwt"
      LOG_LEVEL                         = "info"
    },
  )
  secret_env = {
    DATABASE_URL = {
      secret = module.secrets.secret_ids[local.database_secret_id]
    }
    DSN = {
      secret = module.secrets.secret_ids[local.database_secret_id]
    }
    SECRETS_SYSTEM = {
      secret = "identity-oauth2-hydra-secrets-system"
    }
    SECRETS_COOKIE = {
      secret = "identity-oauth2-hydra-secrets-cookie"
    }
    WEBHOOK_BEARER_PSK = {
      secret = "hydra-webhook-psk"
    }
  }

  depends_on = [
    module.secrets,
    module.messaging,
    module.migrate,
  ]
}
