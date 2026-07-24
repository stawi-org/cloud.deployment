# Repeatable Cloud Run + Neon + Pub/Sub app root.
# Account selection (which GCP project / Neon org) is OUTSIDE this file:
#   app.yaml → config/gcp-accounts.yaml + config/neon-accounts.yaml → CI vars.
#
# Secrets that must not live in git:
#   - neon_api_key (deploy-time provider) from SOPS credentials (CI)
#   - DATABASE_URL and extra secrets in GCP Secret Manager for runtime

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
  region_id = var.neon_region_id
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = substr(replace(var.app_name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.app_name}"
}

locals {
  database_secret_id = "${var.app_name}-database-url"
  # Secret IDs created in SM (values seeded by scripts/seed-gcp-secrets.sh except DATABASE_URL)
  app_secret_ids = toset([
    "identity-authentication-csrf-secret",
    "identity-authentication-cookie-hash-key",
    "identity-authentication-cookie-block-key",
    "hydra-webhook-psk",
  ])
  google_secret_ids = toset(compact([
    var.google_oauth_client_id != "" ? "identity-authentication-google-oauth-client-id" : null,
    var.google_oauth_client_secret != "" ? "identity-authentication-google-oauth-client-secret" : null,
  ]))
  secret_ids = setunion(
    toset([local.database_secret_id]),
    local.app_secret_ids,
    local.google_secret_ids,
    var.extra_secret_ids,
  )
  # Literals only — never keys() of sensitive maps
  version_ids = setunion(
    toset([local.database_secret_id]),
    local.app_secret_ids,
    local.google_secret_ids,
  )
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    local.generated_secret_values,
    var.google_oauth_client_id != "" ? {
      "identity-authentication-google-oauth-client-id" = var.google_oauth_client_id
    } : {},
    var.google_oauth_client_secret != "" ? {
      "identity-authentication-google-oauth-client-secret" = var.google_oauth_client_secret
    } : {},
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

module "service" {
  source                = "../../../modules/cloudrun-service"
  name                  = var.app_name
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  labels                = var.labels
  service_account_email = google_service_account.runtime.email
  env = merge(
    module.edge.service_env,
    module.messaging.service_env,
    {
      GCP_PROJECT = var.project_id
      APP_NAME    = var.app_name
    },
  )
  secret_env = merge(
    {
      DATABASE_URL = {
        secret = module.secrets.secret_ids[local.database_secret_id]
      }
      CSRF_SECRET = {
        secret = "identity-authentication-csrf-secret"
      }
      SECURE_COOKIE_HASH_KEY = {
        secret = "identity-authentication-cookie-hash-key"
      }
      SECURE_COOKIE_BLOCK_KEY = {
        secret = "identity-authentication-cookie-block-key"
      }
      HYDRA_WEBHOOK_PSK = {
        secret = "hydra-webhook-psk"
      }
    },
    var.google_oauth_client_id != "" ? {
      GOOGLE_OAUTH_CLIENT_ID = { secret = "identity-authentication-google-oauth-client-id" }
    } : {},
    var.google_oauth_client_secret != "" ? {
      GOOGLE_OAUTH_CLIENT_SECRET = { secret = "identity-authentication-google-oauth-client-secret" }
    } : {},
  )

  depends_on = [
    module.secrets,
    module.messaging,
  ]
}
