# service-authentication-tenancy — self-contained.
# Parity: namespaces/identity/tenancy/service-tenancy.yaml

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
  is_prod         = var.platform == "stawi-prod"
  accounts_origin = local.is_prod ? "https://accounts.stawi.org" : "https://accounts.stawi.dev"
  oauth2_origin   = local.is_prod ? "https://oauth2.stawi.org" : "https://oauth2.stawi.dev"
  api_base        = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"
  issuer          = local.is_prod ? "https://stawi.org" : "https://stawi.dev"
  token_url       = "${local.oauth2_origin}/oauth2/token"

  database_secret_id        = "${var.app_name}-database-url"
  database_direct_secret_id = "${var.app_name}-database-url-direct"
  secret_ids                = setunion(toset([local.database_secret_id, local.database_direct_secret_id]), var.extra_secret_ids)
  version_ids               = toset([local.database_secret_id, local.database_direct_secret_id])
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    { (local.database_direct_secret_id) = module.db.connection_uri },
    var.extra_secret_values,
  )

  app_env = {
    HTTP_PORT                        = "8080"
    LOG_LEVEL                        = "INFO"
    DATABASE_LOG_QUERIES             = "False"
    SYNCHRONISE_PRIMARY_PARTITIONS   = "True"
    AUTHORIZATION_MODE               = "keto"
    OAUTH2_SERVICE_URI               = local.oauth2_origin
    OAUTH2_SERVICE_ADMIN_URI         = local.oauth2_origin
    OAUTH2_WELL_KNOWN_OIDC_PATH      = ".well-known/openid-configuration"
    OAUTH2_AUDIENCE_BASE_URL         = local.api_base
    OAUTH2_CLIENT_ASSERTION_AUDIENCE = local.token_url
    OAUTH2_TOKEN_ENDPOINT_AUTH_METHOD = "private_key_jwt"
    OAUTH2_JWT_VERIFY_ISSUER         = local.issuer
    OAUTH2_SERVICE_CLIENT_ID         = var.app_name
    OAUTH2_RESOURCE_AUDIENCE         = "${local.api_base}/tenancy"
    OAUTH2_REQUESTED_AUDIENCES       = join(",", ["${local.api_base}/tenancy", "${local.api_base}/profile", "${local.api_base}/notification"])
    OAUTH2_PRIVATE_JWT_KEY = jsonencode({
      source     = "url"
      signer_url = "${local.accounts_origin}/webhook/sign/private-key-jwt"
      key_id     = "hydra.openid.id-token"
    })
    KETO_SERVICE_ADMIN_URI           = local.api_base
    AUTHORIZATION_SERVICE_READ_URI   = local.api_base
    AUTHORIZATION_SERVICE_WRITE_URI  = local.api_base
    EVENTS_QUEUE_URL                 = "mem://frame.events.internal._queue"
    EVENTS_QUEUE_NAME                = "frame.events.internal_._queue"
    OTEL_EXPORTER_OTLP_TIMEOUT       = "10000"
    OTEL_EXPORTER_OTLP_TRACES_TIMEOUT = "10000"
    OTEL_EXPORTER_OTLP_METRICS_TIMEOUT = "10000"
    OTEL_EXPORTER_OTLP_LOGS_TIMEOUT  = "10000"
    OTEL_BSP_EXPORT_TIMEOUT          = "10000"
    OTEL_BSP_MAX_QUEUE_SIZE          = "512"
    OTEL_BLRP_EXPORT_TIMEOUT         = "10000"
    OTEL_BLRP_MAX_QUEUE_SIZE         = "512"
    OTEL_METRIC_EXPORT_TIMEOUT       = "10000"
    GCP_PROJECT                      = var.project_id
    APP_NAME                         = var.app_name
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

resource "google_secret_manager_secret_iam_member" "hydra_webhook_psk" {
  project   = var.project_id
  secret_id = "hydra-webhook-psk"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
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
  args                  = ["migrate"]
  timeout               = "900s"
  # Tenancy migrate initializes profile client → needs OAuth token endpoint envs.
  env = {
    LOG_LEVEL                         = "INFO"
    EVENTS_QUEUE_URL                  = "mem://frame.events.migrate"
    OTEL_TRACES_EXPORTER              = "none"
    OTEL_METRICS_EXPORTER             = "none"
    OTEL_LOGS_EXPORTER                = "none"
    PERMISSIONS_REGISTRATION_URL      = "${local.api_base}/tenancy/_internal/register/permissions"
    OAUTH2_SERVICE_URI                = local.oauth2_origin
    OAUTH2_SERVICE_ADMIN_URI          = local.oauth2_origin
    OAUTH2_WELL_KNOWN_OIDC_PATH       = ".well-known/openid-configuration"
    OAUTH2_CLIENT_ASSERTION_AUDIENCE  = local.token_url
    OAUTH2_TOKEN_ENDPOINT_AUTH_METHOD = "private_key_jwt"
    OAUTH2_JWT_VERIFY_ISSUER          = local.issuer
    OAUTH2_SERVICE_CLIENT_ID          = var.app_name
    OAUTH2_RESOURCE_AUDIENCE          = "${local.api_base}/tenancy"
    OAUTH2_PRIVATE_JWT_KEY = jsonencode({
      source     = "url"
      signer_url = "${local.accounts_origin}/webhook/sign/private-key-jwt"
      key_id     = "hydra.openid.id-token"
    })
    PROFILE_SERVICE_URI = "${local.api_base}/profile"
  }
  secret_env = {
    DATABASE_URL          = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
    OAUTH2_SIGNER_API_KEY = { secret = "hydra-webhook-psk" }
  }
  depends_on = [module.secrets, google_secret_manager_secret_iam_member.hydra_webhook_psk]
}

module "service" {
  source                = "../../../modules/cloudrun-service"
  name                  = var.app_name
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  labels                = var.labels
  service_account_email = google_service_account.runtime.email
  container_port        = 8080
  memory                = "512Mi"
  env = merge(
    module.edge.service_env,
    module.messaging.service_env,
    local.app_env,
  )
  secret_env = {
    DATABASE_URL          = { secret = module.secrets.secret_ids[local.database_secret_id] }
    REPLICA_DATABASE_URL  = { secret = module.secrets.secret_ids[local.database_secret_id] }
    OAUTH2_SIGNER_API_KEY = { secret = "hydra-webhook-psk" }
  }

  depends_on = [module.secrets, module.messaging, module.migrate, google_secret_manager_secret_iam_member.hydra_webhook_psk]
}

# Cluster CronJob tenancy-sync-jobs — job definition only (not executed every apply).
module "sync_job" {
  source                = "../../../modules/cloudrun-migrate-job"
  name                  = "${var.app_name}-sync-partitions"
  project_id            = var.project_id
  region                = var.region
  image                 = "curlimages/curl:8.20.0"
  service_account_email = google_service_account.runtime.email
  labels                = var.labels
  args = [
    "-sS", "-X", "POST",
    "--retry", "8", "--retry-all-errors",
    "-o", "/dev/null", "-w", "%%{http_code}",
    "${local.api_base}/tenancy/_internal/sync/clients",
  ]
  execute    = false
  depends_on = [module.service]
}
