# service-authentication — self-contained.
# Parity: namespaces/identity/authentication/service-authentication.yaml

provider "neon" {
  api_key = var.neon_api_key
}

provider "google" {
  project = var.project_id
  region  = var.region
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

locals {
  is_prod         = var.platform == "stawi-prod"
  accounts_origin = local.is_prod ? "https://accounts.stawi.org" : "https://accounts.stawi.dev"
  oauth2_edge     = local.is_prod ? "https://oauth2.stawi.org" : "https://oauth2.stawi.dev"
  # Prefer Cloud Run Hydra until public edge (oauth2.stawi.*) is mapped.
  oauth2_origin   = data.google_cloud_run_v2_service.hydra.uri
  api_base        = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"
  issuer          = local.is_prod ? "https://stawi.org" : "https://stawi.dev"
  token_url       = "${local.oauth2_origin}/oauth2/token"

  database_secret_id        = "${var.app_name}-database-url"
  database_direct_secret_id = "${var.app_name}-database-url-direct"
  app_secret_ids = toset([
    "identity-authentication-csrf-secret",
    "identity-authentication-cookie-hash-key",
    "identity-authentication-cookie-block-key",
  ])
  # Conditions must not mark for_each keys sensitive (random/SOPS values are sensitive).
  google_secret_ids = toset(compact([
    try(nonsensitive(var.google_oauth_client_id), "") != "" ? "identity-authentication-google-oauth-client-id" : null,
    try(nonsensitive(var.google_oauth_client_secret), "") != "" ? "identity-authentication-google-oauth-client-secret" : null,
  ]))
  secret_ids = setunion(
    toset([local.database_secret_id, local.database_direct_secret_id]),
    local.app_secret_ids,
    local.google_secret_ids,
    var.extra_secret_ids,
  )
  version_ids = setunion(
    toset([local.database_secret_id, local.database_direct_secret_id]),
    local.app_secret_ids,
    local.google_secret_ids,
  )
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    { (local.database_direct_secret_id) = module.db.connection_uri },
    local.generated_secret_values,
    var.google_oauth_client_id != "" ? {
      "identity-authentication-google-oauth-client-id" = var.google_oauth_client_id
    } : {},
    var.google_oauth_client_secret != "" ? {
      "identity-authentication-google-oauth-client-secret" = var.google_oauth_client_secret
    } : {},
    var.extra_secret_values,
  )

  # Colony oauth2 block → Frame env (this app only)
  app_env = {
    HTTP_PORT                             = "8080"
    LOG_LEVEL                             = "INFO"
    EXPOSE_ERRORS                         = "false"
    AUTHORIZATION_MODE                    = "keto"
    OAUTH2_SERVICE_URI                    = local.oauth2_origin
    OAUTH2_SERVICE_ADMIN_URI              = local.oauth2_origin
    OAUTH2_WELL_KNOWN_OIDC_PATH           = ".well-known/openid-configuration"
    OAUTH2_AUDIENCE_BASE_URL              = local.api_base
    OAUTH2_CLIENT_ASSERTION_AUDIENCE      = local.token_url
    OAUTH2_CLIENT_ASSERTION_AUD             = local.token_url
    OAUTH2_TOKEN_ENDPOINT_AUTH_METHOD     = "private_key_jwt"
    OAUTH2_JWT_VERIFY_ISSUER              = local.issuer
    OAUTH2_SERVICE_CLIENT_ID              = var.app_name
    OAUTH2_RESOURCE_AUDIENCE              = "${local.api_base}/authentication"
    OAUTH2_REQUESTED_AUDIENCES            = join(",", ["${local.api_base}/profile", "${local.api_base}/tenancy", "${local.api_base}/devices", "${local.api_base}/files"])
    OAUTH2_PRIVATE_JWT_KEY = jsonencode({
      source     = "url"
      signer_url = "${local.accounts_origin}/webhook/sign/private-key-jwt"
      key_id     = "hydra.openid.id-token"
    })
    PROFILE_SERVICE_URI                   = "${local.api_base}/profile"
    TENANCY_SERVICE_URI                   = "${local.api_base}/tenancy"
    AUTHORIZATION_SERVICE_READ_URI        = local.api_base
    AUTHORIZATION_SERVICE_WRITE_URI       = local.api_base
    DEVICE_SERVICE_URI                    = "${local.api_base}/devices"
    FILES_SERVICE_URI                     = "${local.api_base}/files"
    DEFAULT_TENANT_ID                     = "c2f4j7au6s7f91uqnojg"
    DEFAULT_PARTITION_ID                  = "c2f4j7au6s7f91uqnokg"
    FEDCM_PUBLIC_ORIGIN                   = local.accounts_origin
    FEDCM_HYDRA_PUBLIC_URL                = local.oauth2_origin
    OAUTH2_HYDRA_PUBLIC_INTERNAL_URL      = local.oauth2_origin
    NATIVE_CREDENTIAL_EXCHANGE_ENABLED    = "true"
    AUTH_PROVIDER_GOOGLE_CALLBACK_URL     = "${local.accounts_origin}/s/social/callback"
    AUTH_PROVIDER_GOOGLE_SCOPES           = "openid email profile"
    # EVENTS_QUEUE_* from module.messaging.service_env (gcppubsub + handlers)
    OTEL_EXPORTER_OTLP_TIMEOUT            = "10000"
    OTEL_EXPORTER_OTLP_TRACES_TIMEOUT     = "10000"
    OTEL_EXPORTER_OTLP_METRICS_TIMEOUT    = "10000"
    OTEL_EXPORTER_OTLP_LOGS_TIMEOUT       = "10000"
    OTEL_BSP_EXPORT_TIMEOUT               = "10000"
    OTEL_BSP_MAX_QUEUE_SIZE               = "512"
    OTEL_BLRP_EXPORT_TIMEOUT              = "10000"
    OTEL_BLRP_MAX_QUEUE_SIZE              = "512"
    OTEL_METRIC_EXPORT_TIMEOUT            = "10000"
    GCP_PROJECT                           = var.project_id
    APP_NAME                              = var.app_name
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

# Shared PSK owned by identity-oauth2-hydra
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
  env = {
    LOG_LEVEL                    = "INFO"
    TRACE_REQUESTS               = "false"
    EVENTS_QUEUE_URL             = "mem://frame.events.migrate"
    OTEL_TRACES_EXPORTER         = "none"
    OTEL_METRICS_EXPORTER        = "none"
    OTEL_LOGS_EXPORTER           = "none"
    PERMISSIONS_REGISTRATION_URL = "${local.api_base}/tenancy/_internal/register/permissions"
  }
  secret_env = {
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
  container_port        = 8080
  memory                = "1Gi"
  cpu                   = "1"
  startup_probe_path    = "/healthz"
  liveness_probe_path   = "/healthz"
  env = merge(
    module.edge.service_env,
    module.messaging.service_env,
    local.app_env,
  )
  secret_env = merge(
    {
      DATABASE_URL            = { secret = module.secrets.secret_ids[local.database_secret_id] }
      REPLICA_DATABASE_URL    = { secret = module.secrets.secret_ids[local.database_secret_id] }
      CSRF_SECRET             = { secret = "identity-authentication-csrf-secret" }
      SECURE_COOKIE_HASH_KEY  = { secret = "identity-authentication-cookie-hash-key" }
      SECURE_COOKIE_BLOCK_KEY = { secret = "identity-authentication-cookie-block-key" }
      HYDRA_WEBHOOK_API_PSK   = { secret = "hydra-webhook-psk" }
      OAUTH2_SIGNER_API_KEY   = { secret = "hydra-webhook-psk" }
    },
    var.google_oauth_client_id != "" ? {
      AUTH_PROVIDER_GOOGLE_CLIENT_ID = { secret = "identity-authentication-google-oauth-client-id" }
    } : {},
    var.google_oauth_client_secret != "" ? {
      AUTH_PROVIDER_GOOGLE_SECRET = { secret = "identity-authentication-google-oauth-client-secret" }
    } : {},
  )

  depends_on = [
    module.secrets,
    module.messaging,
    module.migrate,
    google_secret_manager_secret_iam_member.hydra_webhook_psk,
  ]
}
