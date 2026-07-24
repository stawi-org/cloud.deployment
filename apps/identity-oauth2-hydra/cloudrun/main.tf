# Ory Hydra — parity with namespaces/identity/oauth2/service-hydra.yaml

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "domain" {
  source = "../../../modules/identity-domain"
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
  token_hook_secret_id      = "${var.app_name}-token-hook-auth"
  app_secret_ids = toset([
    "identity-oauth2-hydra-secrets-system",
    "identity-oauth2-hydra-secrets-cookie",
    "hydra-webhook-psk",
    local.token_hook_secret_id,
  ])
  secret_ids  = setunion(toset([local.database_secret_id, local.database_direct_secret_id]), local.app_secret_ids, var.extra_secret_ids)
  version_ids = setunion(toset([local.database_secret_id, local.database_direct_secret_id]), local.app_secret_ids)
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    { (local.database_direct_secret_id) = module.db.connection_uri },
    local.generated_secret_values,
    {
      (local.token_hook_secret_id) = jsonencode({
        in    = "header"
        name  = "Authorization"
        value = "Bearer ${local.generated_secret_values["hydra-webhook-psk"]}"
      })
    },
    var.extra_secret_values,
  )
}

module "secrets" {
  source           = "../../../modules/app-secrets"
  project_id       = var.project_id
  labels           = var.labels
  secret_ids       = local.secret_ids
  version_ids      = local.version_ids
  secret_values    = local.secret_values
  accessor_members = ["serviceAccount:${google_service_account.runtime.email}"]
}

module "messaging" {
  source                        = "../../../modules/pubsub"
  project_id                    = var.project_id
  app_name                      = var.app_name
  runtime_service_account_email = google_service_account.runtime.email
  labels                        = var.labels
}

module "migrate" {
  source                = "../../../modules/cloudrun-migrate-job"
  name                  = "${var.app_name}-migrate"
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  service_account_email = google_service_account.runtime.email
  labels                = var.labels
  args                  = ["migrate", "sql", "-e", "--yes"]
  env                   = { LOG_LEVEL = "info" }
  secret_env = {
    DSN          = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
    DATABASE_URL = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
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
  memory                = "512Mi"
  env = merge(
    module.domain.hydra_env,
    module.messaging.service_env,
    {
      GCP_PROJECT = var.project_id
      APP_NAME    = var.app_name
    },
  )
  secret_env = {
    DSN                          = { secret = module.secrets.secret_ids[local.database_secret_id] }
    DATABASE_URL                 = { secret = module.secrets.secret_ids[local.database_secret_id] }
    SECRETS_SYSTEM               = { secret = "identity-oauth2-hydra-secrets-system" }
    SECRETS_COOKIE               = { secret = "identity-oauth2-hydra-secrets-cookie" }
    WEBHOOK_BEARER_PSK           = { secret = "hydra-webhook-psk" }
    OAUTH2_TOKEN_HOOK_AUTH_CONFIG = { secret = local.token_hook_secret_id }
  }

  depends_on = [module.secrets, module.messaging, module.migrate]
}
