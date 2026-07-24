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
  app_secret_ids = toset([
    "identity-oauth2-hydra-secrets-system",
    "identity-oauth2-hydra-secrets-cookie",
    "hydra-webhook-psk",
  ])
  secret_ids = setunion(
    toset([local.database_secret_id]),
    local.app_secret_ids,
    var.extra_secret_ids,
    toset(keys(var.extra_secret_values)),
  )
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    local.generated_secret_values,
    var.extra_secret_values,
  )
}

module "secrets" {
  source = "../../../modules/app-secrets"

  project_id = var.project_id
  labels     = var.labels

  secret_ids    = local.secret_ids
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
  secret_env = {
    DATABASE_URL = {
      secret = module.secrets.secret_ids[local.database_secret_id]
    }
    # Hydra chart/env often expects DSN — same payload as DATABASE_URL
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
  ]
}
