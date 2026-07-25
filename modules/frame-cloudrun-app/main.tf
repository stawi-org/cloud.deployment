# Frame Cloud Run application — single composition for identity / ops / platform.
#
# Order: identity data → edge → SA → Neon → secrets → messaging → migrate →
#        service → keep-warm → push IAM.
#
# Escape hatches live on the module variables (custom topics, secret_env_extra,
# app_env, min_instance_count). Hydra/Keto/edge-lb stay outside this module.

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  identity_project = coalesce(var.identity_project_id, var.project_id)
  identity_region  = coalesce(var.identity_region, var.region)

  is_prod         = var.platform == "stawi-prod"
  accounts_origin = local.is_prod ? "https://accounts.stawi.org" : "https://accounts.stawi.dev"
  api_base        = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"
  issuer          = local.is_prod ? "https://stawi.org" : "https://stawi.dev"

  # Strip domain prefix when app is domain-scoped (operations-audit → /audit).
  default_resource_path = (
    startswith(var.app_name, "operations-") ? "/${trimprefix(var.app_name, "operations-")}" :
    startswith(var.app_name, "identity-") ? "/${trimprefix(var.app_name, "identity-")}" :
    startswith(var.app_name, "platform-") ? "/${trimprefix(var.app_name, "platform-")}" :
    "/${var.app_name}"
  )
  resource_path = var.resource_path != "" ? var.resource_path : local.default_resource_path
  audience_paths        = distinct(concat([local.resource_path], var.requested_audience_paths))

  service_run_url      = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  events_ref           = "${var.app_name}-events"
  events_push_endpoint = "${local.service_run_url}/_frame/queue/${local.events_ref}"

  # Shared OIDC audience: multi-topic uses service root; default uses full push URL.
  resolved_push_oidc_audience = (
    var.push_oidc_audience != ""
    ? var.push_oidc_audience
    : (
      length(var.messaging_subscriptions) > 0
      ? local.service_run_url
      : local.events_push_endpoint
    )
  )

  database_secret_id        = "${var.app_name}-database-url"
  database_direct_secret_id = "${var.app_name}-database-url-direct"

  # for_each keys must never be sensitive (keys() of a sensitive map is sensitive).
  extra_version_ids = (
    length(var.extra_version_ids) > 0
    ? var.extra_version_ids
    : (
      length(var.extra_secret_values) > 0
      ? nonsensitive(toset(keys(var.extra_secret_values)))
      : toset([])
    )
  )

  secret_ids = setunion(
    var.has_database ? toset([local.database_secret_id, local.database_direct_secret_id]) : toset([]),
    var.extra_secret_ids,
  )
  version_ids = setunion(
    var.has_database ? toset([local.database_secret_id, local.database_direct_secret_id]) : toset([]),
    local.extra_version_ids,
  )
  secret_values = merge(
    var.has_database ? {
      (local.database_secret_id)        = module.db[0].pooled_connection_uri
      (local.database_direct_secret_id) = module.db[0].connection_uri
    } : {},
    var.extra_secret_values,
  )

  oauth2_origin = data.google_cloud_run_v2_service.hydra.uri
  token_url     = "${local.oauth2_origin}/oauth2/token"

  keto_read_uri  = var.enable_keto ? data.google_cloud_run_v2_service.keto_read[0].uri : local.api_base
  keto_write_uri = var.enable_keto ? data.google_cloud_run_v2_service.keto_write[0].uri : local.api_base

  frame_oauth_env = merge(
    {
      HTTP_PORT                         = tostring(var.container_port)
      SERVER_PORT                       = ":${var.container_port}"
      LOG_LEVEL                         = "INFO"
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
      OAUTH2_RESOURCE_AUDIENCE          = "${local.api_base}${local.resource_path}"
      OAUTH2_REQUESTED_AUDIENCES        = join(",", [for p in local.audience_paths : "${local.api_base}${p}"])
      OAUTH2_PRIVATE_JWT_KEY = jsonencode({
        source     = "url"
        signer_url = "${local.accounts_origin}/webhook/sign/private-key-jwt"
        key_id     = "hydra.openid.id-token"
      })
      AUTHORIZATION_SERVICE_READ_URI     = local.keto_read_uri
      AUTHORIZATION_SERVICE_WRITE_URI    = local.keto_write_uri
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
    },
    var.enable_keto && var.enable_keto_admin ? {
      KETO_SERVICE_ADMIN_URI = local.keto_write_uri
    } : {},
    var.disable_otel_exporters ? {
      OTEL_TRACES_EXPORTER  = "none"
      OTEL_METRICS_EXPORTER = "none"
      OTEL_LOGS_EXPORTER    = "none"
    } : {},
  )

  migrate_env_default = merge(
    {
      LOG_LEVEL             = "INFO"
      EVENTS_QUEUE_URL      = "mem://frame.events.migrate"
      OTEL_TRACES_EXPORTER  = "none"
      OTEL_METRICS_EXPORTER = "none"
      OTEL_LOGS_EXPORTER    = "none"
    },
    var.permissions_registration ? {
      PERMISSIONS_REGISTRATION_URL = "${local.api_base}/tenancy/_internal/register/permissions"
    } : {},
    var.migrate_env,
  )

  service_secret_env = merge(
    var.has_database ? {
      DATABASE_URL         = { secret = module.secrets.secret_ids[local.database_secret_id] }
      REPLICA_DATABASE_URL = { secret = module.secrets.secret_ids[local.database_secret_id] }
    } : {},
    var.oauth_signer_secret != "" ? {
      OAUTH2_SIGNER_API_KEY = { secret = var.oauth_signer_secret }
    } : {},
    var.secret_env_extra,
  )
}

# ---------------------------------------------------------------------------
# Identity Cloud Run endpoints
# ---------------------------------------------------------------------------

data "google_cloud_run_v2_service" "hydra" {
  name     = "identity-oauth2-hydra"
  location = local.identity_region
  project  = local.identity_project
}

data "google_cloud_run_v2_service" "keto_read" {
  count    = var.enable_keto ? 1 : 0
  name     = "identity-authorization-keto-read"
  location = local.identity_region
  project  = local.identity_project
}

data "google_cloud_run_v2_service" "keto_write" {
  count    = var.enable_keto ? 1 : 0
  name     = "identity-authorization-keto-write"
  location = local.identity_region
  project  = local.identity_project
}

# ---------------------------------------------------------------------------
# Edge + runtime SA + Neon
# ---------------------------------------------------------------------------

module "edge" {
  source = "../edge-contract"
  env    = var.platform
}

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = substr(replace(var.app_name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.app_name}"
}

module "db" {
  count     = var.has_database ? 1 : 0
  source    = "../neon-database"
  app_name  = var.app_name
  org_id    = var.neon_org_id
  region_id = var.neon_region_id
  extensions = length(var.neon_extensions) > 0 ? var.neon_extensions : [
    "uuid-ossp",
    "pg_stat_statements",
    "pg_trgm",
    "btree_gin",
    "btree_gist",
  ]
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

module "secrets" {
  source     = "../app-secrets"
  project_id = var.project_id
  labels     = var.labels
  # Force unmarked sets — OpenTofu panics if for_each keys are sensitive-marked.
  secret_ids       = nonsensitive(local.secret_ids)
  version_ids      = nonsensitive(local.version_ids)
  secret_values    = local.secret_values
  accessor_members = ["serviceAccount:${google_service_account.runtime.email}"]
}

resource "google_secret_manager_secret_iam_member" "oauth_signer" {
  count = (
    var.grant_oauth_signer_accessor
    && var.oauth_signer_secret != ""
    && !contains(var.extra_secret_ids, var.oauth_signer_secret)
  ) ? 1 : 0

  project   = var.project_id
  secret_id = var.oauth_signer_secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

# ---------------------------------------------------------------------------
# Messaging
# ---------------------------------------------------------------------------

module "messaging" {
  count  = var.enable_messaging ? 1 : 0
  source = "../pubsub"

  project_id                    = var.project_id
  app_name                      = var.app_name
  region                        = var.region
  runtime_service_account_email = google_service_account.runtime.email
  labels                        = var.labels

  allowed_persistence_regions = [var.region]
  enforce_in_transit          = false

  create_default_events_topic = length(var.messaging_topics) > 0 ? false : var.create_default_events_topic
  default_push_endpoint = (
    length(var.messaging_subscriptions) > 0
    ? null
    : (var.create_default_events_topic || length(var.messaging_topics) == 0 ? local.events_push_endpoint : null)
  )
  push_oidc_service_account_email = google_service_account.runtime.email
  push_oidc_audience              = local.resolved_push_oidc_audience
  pubsub_service_agent_email      = "service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  create_dead_letter_topic        = var.create_dead_letter_topic

  topics        = var.messaging_topics
  subscriptions = var.messaging_subscriptions
}

# ---------------------------------------------------------------------------
# Migrate job
# ---------------------------------------------------------------------------

module "migrate" {
  count                 = var.has_database ? 1 : 0
  source                = "../cloudrun-migrate-job"
  name                  = "${var.app_name}-migrate"
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  service_account_email = google_service_account.runtime.email
  labels                = var.labels
  execute               = var.migrate_execute
  args                  = var.migrate_args
  env                   = local.migrate_env_default
  secret_env = merge(
    {
      DATABASE_URL = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
    },
    var.migrate_secret_env_extra,
  )
  depends_on = [module.secrets, module.db]
}

# ---------------------------------------------------------------------------
# Cloud Run service
# ---------------------------------------------------------------------------

module "service" {
  source                = "../cloudrun-service"
  name                  = var.app_name
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  labels                = var.labels
  service_account_email = google_service_account.runtime.email
  container_port        = var.container_port
  use_http2             = var.use_http2
  memory                = var.memory
  cpu                   = var.cpu
  min_instance_count    = var.min_instance_count
  max_instance_count    = var.max_instance_count
  public_invoker        = var.public_invoker
  startup_probe_path    = var.startup_probe_path
  liveness_probe_path   = var.liveness_probe_path

  env = merge(
    module.edge.service_env,
    var.enable_messaging ? module.messaging[0].service_env : {},
    local.frame_oauth_env,
    var.service_env_extra,
    var.app_env,
  )
  secret_env = local.service_secret_env

  depends_on = [
    module.secrets,
    module.messaging,
    module.db,
    module.migrate,
    google_secret_manager_secret_iam_member.oauth_signer,
  ]
}

# ---------------------------------------------------------------------------
# Keep-warm (optional)
# ---------------------------------------------------------------------------

module "keep_warm" {
  count            = var.enable_keep_warm ? 1 : 0
  source           = "../cloudrun-keep-warm"
  project_id       = var.project_id
  name             = "keep-warm-${var.app_name}"
  uri              = "${module.service.uri}${var.keep_warm_path}"
  schedule         = var.keep_warm_schedule
  attempt_deadline = "180s"
  scheduler_region = var.keep_warm_scheduler_region
  depends_on       = [module.service]
}

# ---------------------------------------------------------------------------
# Pub/Sub push OIDC IAM
# ---------------------------------------------------------------------------

resource "google_service_account_iam_member" "pubsub_push_token_creator" {
  count = var.enable_messaging ? 1 : 0

  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_cloud_run_v2_service_iam_member" "pubsub_push_invoker" {
  count = var.enable_messaging ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = module.service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.runtime.email}"
}
