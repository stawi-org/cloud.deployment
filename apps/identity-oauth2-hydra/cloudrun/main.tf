# Ory Hydra — self-contained. Parity: namespaces/identity/oauth2/service-hydra.yaml

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
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

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  is_prod         = var.platform == "stawi-prod"
  accounts_origin = local.is_prod ? "https://accounts.stawi.org" : "https://accounts.stawi.dev"
  # Public edge host (DNS later). Until mapped, Cloud Run URL is used for discovery/token.
  oauth2_edge   = local.is_prod ? "https://oauth2.stawi.org" : "https://oauth2.stawi.dev"
  oauth2_run    = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  oauth2_origin = local.oauth2_run
  api_base      = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"
  issuer        = local.is_prod ? "https://stawi.org" : "https://stawi.dev"
  cookie_domain = local.is_prod ? "stawi.org" : "stawi.dev"

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
    # Only the auth.config object — type is OAUTH2_TOKEN_HOOK_AUTH_TYPE env (see hydra_env).
    # See ory/hydra#3959: consolidated CONFIG_VALUE style is ignored; AUTH_CONFIG is config only.
    {
      (local.token_hook_secret_id) = jsonencode({
        in    = "header"
        name  = "Authorization"
        value = "Bearer ${local.generated_secret_values["hydra-webhook-psk"]}"
      })
    },
    var.extra_secret_values,
  )

  # Cluster Helm hydra.config → env (public edge only)
  hydra_env = {
    # Cloud Run requires listen on all interfaces (not localhost)
    SERVE_PUBLIC_HOST                                = "0.0.0.0"
    SERVE_PUBLIC_PORT                                = "4444"
    SERVE_PUBLIC_BASE_URL                            = local.oauth2_origin
    SERVE_PUBLIC_CORS_ENABLED                        = "false"
    SERVE_PUBLIC_COOKIES_DOMAIN                      = local.cookie_domain
    SERVE_PUBLIC_COOKIES_SAME_SITE_MODE              = "Lax"
    SERVE_PUBLIC_COOKIES_SECURE                      = "true"
    SERVE_PUBLIC_REQUEST_LOG_DISABLE_FOR_HEALTH      = "true"
    URLS_LOGIN                                       = "${local.accounts_origin}/s/login"
    URLS_CONSENT                                     = "${local.accounts_origin}/s/consent"
    URLS_LOGOUT                                      = "${local.accounts_origin}/s/logout"
    URLS_ERROR                                       = "${local.accounts_origin}/error"
    URLS_POST_LOGOUT_REDIRECT                        = "${local.accounts_origin}/logout-successful"
    URLS_SELF_PUBLIC                                 = local.oauth2_origin
    URLS_SELF_ISSUER                                 = local.issuer
    URLS_SELF_ADMIN                                  = local.oauth2_origin
    WEBFINGER_OIDC_DISCOVERY_TOKEN_URL               = "${local.oauth2_origin}/oauth2/token"
    WEBFINGER_OIDC_DISCOVERY_AUTH_URL                = "${local.oauth2_origin}/oauth2/auth"
    WEBFINGER_OIDC_DISCOVERY_CLIENT_REGISTRATION_URL = "${local.oauth2_origin}/clients"
    WEBFINGER_OIDC_DISCOVERY_USERINFO_URL            = "${local.api_base}/profile/public/user/info"
    WEBFINGER_OIDC_DISCOVERY_JWKS_URL                = "${local.oauth2_origin}/.well-known/jwks.json"
    STRATEGIES_ACCESS_TOKEN                          = "jwt"
    STRATEGIES_SCOPE                                 = "wildcard"
    TTL_ACCESS_TOKEN                                 = "1h"
    TTL_REFRESH_TOKEN                                = "2160h"
    TTL_ID_TOKEN                                     = "1h"
    TTL_AUTH_CODE                                    = "10m"
    TTL_AUTHENTICATION_SESSION                       = "2160h"
    TTL_LOGIN_CONSENT_REQUEST                        = "1h"
    OAUTH2_PKCE_ENFORCED                             = "true"
    OAUTH2_PKCE_ENFORCED_FOR_PUBLIC_CLIENTS          = "true"
    OAUTH2_EXCLUDE_NOT_BEFORE_CLAIM                  = "true"
    OAUTH2_MIRROR_TOP_LEVEL_CLAIMS                   = "true"
    OAUTH2_HASHERS_ALGORITHM                         = "bcrypt"
    OAUTH2_HASHERS_BCRYPT_COST                       = "12"
    OAUTH2_SESSION_ENCRYPT_AT_REST                   = "true"
    OAUTH2_EXPOSE_INTERNAL_ERRORS                    = "false"
    OAUTH2_TOKEN_HOOK_URL                            = "${local.accounts_origin}/webhook/enrich/token"
    OAUTH2_TOKEN_HOOK_AUTH_TYPE                      = "api_key"
    SQA_OPT_OUT                                      = "true"
    LOG_LEVEL                                        = "warn"
    LOG_FORMAT                                       = "text"
  }
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
  region                        = var.region
  runtime_service_account_email = google_service_account.runtime.email
  labels                        = var.labels

  # Regional storage only — Hydra is not a Frame consumer (no push handler).
  allowed_persistence_regions = [var.region]
  enforce_in_transit          = false
  create_dead_letter_topic    = false
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
    local.hydra_env,
    module.messaging.service_env,
    {
      GCP_PROJECT = var.project_id
      APP_NAME    = var.app_name
    },
  )
  secret_env = {
    DSN                           = { secret = module.secrets.secret_ids[local.database_secret_id] }
    DATABASE_URL                  = { secret = module.secrets.secret_ids[local.database_secret_id] }
    SECRETS_SYSTEM                = { secret = "identity-oauth2-hydra-secrets-system" }
    SECRETS_COOKIE                = { secret = "identity-oauth2-hydra-secrets-cookie" }
    WEBHOOK_BEARER_PSK            = { secret = "hydra-webhook-psk" }
    OAUTH2_TOKEN_HOOK_AUTH_CONFIG = { secret = local.token_hook_secret_id }
  }

  depends_on = [module.secrets, module.messaging, module.migrate]
}
