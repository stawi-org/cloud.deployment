# service-profile — self-contained.
# Parity: namespaces/identity/profile/service-profile.yaml

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

# Hydra Cloud Run URL for OIDC discovery until oauth2.stawi.org edge is mapped.
data "google_cloud_run_v2_service" "hydra" {
  name     = "identity-oauth2-hydra"
  location = var.region
  project  = var.project_id
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

resource "random_password" "dek_aes" {
  length  = 32
  special = false
}

resource "random_password" "dek_hmac" {
  length  = 32
  special = false
}

locals {
  # Deterministic Cloud Run URL for Pub/Sub push (stable before first deploy).
  service_run_url      = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  events_ref           = "${var.app_name}-events"
  events_push_endpoint = "${local.service_run_url}/_frame/queue/${local.events_ref}"

  is_prod         = var.platform == "stawi-prod"
  accounts_origin = local.is_prod ? "https://accounts.stawi.org" : "https://accounts.stawi.dev"
  oauth2_edge     = local.is_prod ? "https://oauth2.stawi.org" : "https://oauth2.stawi.dev"
  # Prefer Cloud Run Hydra until public edge (oauth2.stawi.*) is mapped.
  oauth2_origin = data.google_cloud_run_v2_service.hydra.uri
  api_base      = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"
  issuer        = local.is_prod ? "https://stawi.org" : "https://stawi.dev"
  token_url     = "${local.oauth2_origin}/oauth2/token"

  database_secret_id        = "${var.app_name}-database-url"
  database_direct_secret_id = "${var.app_name}-database-url-direct"
  dek_ids = toset([
    "identity-profile-dek-key-id",
    "identity-profile-dek-aes-key",
    "identity-profile-dek-hmac-key",
  ])
  secret_ids  = setunion(toset([local.database_secret_id, local.database_direct_secret_id]), local.dek_ids, var.extra_secret_ids)
  version_ids = setunion(toset([local.database_secret_id, local.database_direct_secret_id]), local.dek_ids)
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    { (local.database_direct_secret_id) = module.db.connection_uri },
    {
      "identity-profile-dek-key-id"   = "contacts-dek-cloud"
      "identity-profile-dek-aes-key"  = base64encode(random_password.dek_aes.result)
      "identity-profile-dek-hmac-key" = base64encode(random_password.dek_hmac.result)
    },
    var.extra_secret_values,
  )

  app_env = {
    HTTP_PORT                         = "8080"
    LOG_LEVEL                         = "INFO"
    TRACE_REQUESTS                    = "false"
    DEK_OLD_ENCRYPTION_TOKEN          = ""
    AUTHORIZATION_MODE                = "keto"
    OAUTH2_SERVICE_URI                = local.oauth2_origin
    OAUTH2_SERVICE_ADMIN_URI          = local.oauth2_origin
    OAUTH2_WELL_KNOWN_OIDC_PATH       = ".well-known/openid-configuration"
    OAUTH2_AUDIENCE_BASE_URL          = local.api_base
    OAUTH2_CLIENT_ASSERTION_AUDIENCE  = local.token_url
    OAUTH2_CLIENT_ASSERTION_AUD       = local.token_url
    OAUTH2_TOKEN_ENDPOINT_AUTH_METHOD = "private_key_jwt"
    OAUTH2_JWT_VERIFY_ISSUER          = local.issuer
    OAUTH2_SERVICE_CLIENT_ID          = var.app_name
    OAUTH2_RESOURCE_AUDIENCE          = "${local.api_base}/profile"
    OAUTH2_REQUESTED_AUDIENCES        = join(",", ["${local.api_base}/notification", "${local.api_base}/tenancy", "${local.api_base}/devices"])
    OAUTH2_PRIVATE_JWT_KEY = jsonencode({
      source     = "url"
      signer_url = "${local.accounts_origin}/webhook/sign/private-key-jwt"
      key_id     = "hydra.openid.id-token"
    })
    NOTIFICATION_SERVICE_URI        = "${local.api_base}/notification"
    AUTHORIZATION_SERVICE_READ_URI  = local.api_base
    AUTHORIZATION_SERVICE_WRITE_URI = local.api_base
    # EVENTS_QUEUE_* from module.messaging.service_env (gcppubsub + handlers)
    OTEL_EXPORTER_OTLP_TIMEOUT         = "10000"
    OTEL_EXPORTER_OTLP_TRACES_TIMEOUT  = "10000"
    OTEL_EXPORTER_OTLP_METRICS_TIMEOUT = "10000"
    OTEL_EXPORTER_OTLP_LOGS_TIMEOUT    = "10000"
    OTEL_BSP_EXPORT_TIMEOUT            = "10000"
    OTEL_BSP_MAX_QUEUE_SIZE            = "512"
    OTEL_BLRP_EXPORT_TIMEOUT           = "10000"
    OTEL_BLRP_MAX_QUEUE_SIZE           = "512"
    OTEL_METRIC_EXPORT_TIMEOUT         = "10000"
    GCP_PROJECT                        = var.project_id
    APP_NAME                           = var.app_name
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
  region                        = var.region
  runtime_service_account_email = google_service_account.runtime.email
  labels                        = var.labels

  # Regional storage only (workload region) — avoid multi-continent message hops.
  allowed_persistence_regions = [var.region]
  enforce_in_transit          = false

  # GCP Pub/Sub push → Frame demux (WithRegisterEvents handlers).
  default_push_endpoint           = local.events_push_endpoint
  push_oidc_service_account_email = google_service_account.runtime.email
  push_oidc_audience              = local.events_push_endpoint
  pubsub_service_agent_email      = "service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  create_dead_letter_topic        = true
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
  env = {
    LOG_LEVEL                    = "INFO"
    EVENTS_QUEUE_URL             = "mem://frame.events.migrate"
    OTEL_TRACES_EXPORTER         = "none"
    OTEL_METRICS_EXPORTER        = "none"
    OTEL_LOGS_EXPORTER           = "none"
    PERMISSIONS_REGISTRATION_URL = "${local.api_base}/tenancy/_internal/register/permissions"
  }
  secret_env = {
    DATABASE_URL                = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
    DEK_LOOKUP_TOKEN            = { secret = "identity-profile-dek-hmac-key" }
    DEK_ACTIVE_KEY_ID           = { secret = "identity-profile-dek-key-id" }
    DEK_ACTIVE_ENCRYPTION_TOKEN = { secret = "identity-profile-dek-aes-key" }
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
  container_port        = 8080
  memory                = "512Mi"
  env = merge(
    module.edge.service_env,
    module.messaging.service_env,
    local.app_env,
  )
  secret_env = {
    DATABASE_URL                = { secret = module.secrets.secret_ids[local.database_secret_id] }
    REPLICA_DATABASE_URL        = { secret = module.secrets.secret_ids[local.database_secret_id] }
    DEK_LOOKUP_TOKEN            = { secret = "identity-profile-dek-hmac-key" }
    DEK_ACTIVE_KEY_ID           = { secret = "identity-profile-dek-key-id" }
    DEK_ACTIVE_ENCRYPTION_TOKEN = { secret = "identity-profile-dek-aes-key" }
    OAUTH2_SIGNER_API_KEY       = { secret = "hydra-webhook-psk" }
  }

  depends_on = [module.secrets, module.messaging, module.migrate, google_secret_manager_secret_iam_member.hydra_webhook_psk]
}

# Pub/Sub push OIDC: allow the runtime SA to be used as push identity,
# and allow that identity to invoke the Cloud Run service.
resource "google_service_account_iam_member" "pubsub_push_token_creator" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_cloud_run_v2_service_iam_member" "pubsub_push_invoker" {
  project  = var.project_id
  location = var.region
  name     = module.service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.runtime.email}"
}
