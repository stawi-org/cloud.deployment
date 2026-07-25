# operations-trustage — operations domain (GCP stawi-operations + Neon operations).
# Source parity: deployment.manifests/namespaces/operations

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

data "google_cloud_run_v2_service" "hydra" {
  name     = "identity-oauth2-hydra"
  location = var.identity_region
  project  = var.identity_project_id
}

data "google_cloud_run_v2_service" "keto_read" {
  name     = "identity-authorization-keto-read"
  location = var.identity_region
  project  = var.identity_project_id
}

data "google_cloud_run_v2_service" "keto_write" {
  name     = "identity-authorization-keto-write"
  location = var.identity_region
  project  = var.identity_project_id
}

module "edge" {
  source = "../../../modules/edge-contract"
  env    = var.platform
}

module "db" {
  count     = var.has_database ? 1 : 0
  source    = "../../../modules/neon-database"
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

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = substr(replace(var.app_name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.app_name}"
}

locals {
  service_run_url      = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  events_ref           = "${var.app_name}-events"
  events_push_endpoint = "${local.service_run_url}/_frame/queue/${local.events_ref}"
  # Shared OIDC audience for all Pub/Sub push subscriptions (Frame accepts one).
  push_oidc_audience = local.service_run_url

  # Workflow Pub/Sub topics (NATS JetStream parity on Cloud Run).
  exec_topic_name      = "${var.app_name}-exec"
  wf_events_topic_name = "${var.app_name}-wf-events"
  exec_worker_ref      = "exec-worker"
  event_router_ref     = "event-router"
  exec_worker_push     = "${local.service_run_url}/_frame/queue/${local.exec_worker_ref}"
  event_router_push    = "${local.service_run_url}/_frame/queue/${local.event_router_ref}"

  is_prod         = var.platform == "stawi-prod"
  accounts_origin = local.is_prod ? "https://accounts.stawi.org" : "https://accounts.stawi.dev"
  oauth2_origin   = data.google_cloud_run_v2_service.hydra.uri
  api_base        = local.is_prod ? "https://api.stawi.org" : "https://api.stawi.dev"
  issuer          = local.is_prod ? "https://stawi.org" : "https://stawi.dev"
  token_url       = "${local.oauth2_origin}/oauth2/token"
  resource_path   = var.resource_path != "" ? var.resource_path : "/${trimprefix(var.app_name, "operations-")}"

  database_secret_id        = "${var.app_name}-database-url"
  database_direct_secret_id = "${var.app_name}-database-url-direct"
  secret_ids = var.has_database ? setunion(
    toset([local.database_secret_id, local.database_direct_secret_id]),
    var.extra_secret_ids,
  ) : var.extra_secret_ids
  version_ids = var.has_database ? toset([local.database_secret_id, local.database_direct_secret_id]) : toset([])
  secret_values = merge(
    var.has_database ? {
      (local.database_secret_id)        = module.db[0].pooled_connection_uri
      (local.database_direct_secret_id) = module.db[0].connection_uri
    } : {},
    var.extra_secret_values,
  )

  audience_paths = distinct(concat([local.resource_path], var.requested_audience_paths))

  app_env = merge({
    HTTP_PORT                         = tostring(var.container_port)
    SERVER_PORT                       = ":${var.container_port}"
    LOG_LEVEL                         = "INFO"
    OTEL_TRACES_EXPORTER              = "none"
    OTEL_METRICS_EXPORTER             = "none"
    OTEL_LOGS_EXPORTER                = "none"
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
    AUTHORIZATION_SERVICE_READ_URI     = data.google_cloud_run_v2_service.keto_read.uri
    AUTHORIZATION_SERVICE_WRITE_URI    = data.google_cloud_run_v2_service.keto_write.uri
    KETO_SERVICE_ADMIN_URI             = data.google_cloud_run_v2_service.keto_write.uri
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
    }, {
    DATABASE_POOL_MAX_CONNS      = "50"
    OUTBOX_BATCH_SIZE            = "20"
    DISPATCH_BATCH_SIZE          = "50"
    ADAPTER_HTTP_TIMEOUT_SECONDS = "30"
    CACHE_REQUIRE_VALKEY         = "false"
    # Workflow queues → Pub/Sub (multi-instance). Frame dual-URL:
    #   publish  gcppubsub://{project}/{topic}
    #   receive  push://{ref}?protocol=gcppubsub  → Pub/Sub push to /_frame/queue/{ref}
    QUEUE_EXEC_DISPATCH_NAME     = "exec-dispatch"
    QUEUE_EXEC_DISPATCH_URL      = "gcppubsub://${var.project_id}/${local.exec_topic_name}"
    QUEUE_EXEC_WORKER_NAME       = local.exec_worker_ref
    QUEUE_EXEC_WORKER_URL        = "push://${local.exec_worker_ref}?protocol=gcppubsub"
    QUEUE_EVENT_INGEST_NAME      = "event-ingest"
    QUEUE_EVENT_INGEST_URL       = "gcppubsub://${var.project_id}/${local.wf_events_topic_name}"
    QUEUE_EVENT_ROUTER_NAME      = local.event_router_ref
    QUEUE_EVENT_ROUTER_URL       = "push://${local.event_router_ref}?protocol=gcppubsub"
    # Do not inject NATS consumer_max_ack_pending onto push:// URLs.
    EXEC_WORKER_MAX_ACK_PENDING  = "0"
    EVENT_ROUTER_MAX_ACK_PENDING = "0"
    # Scheduler wake queues stay mem:// (in-process); keep min_instance_count ≥ 1.
  })
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
  source                          = "../../../modules/pubsub"
  project_id                      = var.project_id
  app_name                        = var.app_name
  region                          = var.region
  runtime_service_account_email   = google_service_account.runtime.email
  labels                          = var.labels
  allowed_persistence_regions     = [var.region]
  enforce_in_transit              = false
  create_default_events_topic     = false
  default_push_endpoint           = null
  push_oidc_service_account_email = google_service_account.runtime.email
  # Shared audience so all push OIDC tokens match FRAME_QUEUE_PUSH_OIDC_AUDIENCE.
  push_oidc_audience         = local.push_oidc_audience
  pubsub_service_agent_email = "service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  create_dead_letter_topic   = true

  topics = {
    events = {
      name = local.events_ref
    }
    exec = {
      name = local.exec_topic_name
    }
    wf_events = {
      name = local.wf_events_topic_name
    }
  }

  subscriptions = {
    events = {
      topic_key             = "events"
      name                  = "${local.events_ref}-push"
      push_endpoint         = local.events_push_endpoint
      enable_subscriber_iam = false
    }
    exec_worker = {
      topic_key             = "exec"
      name                  = "${var.app_name}-exec-worker-push"
      push_endpoint         = local.exec_worker_push
      enable_subscriber_iam = false
      ack_deadline_seconds  = 60
    }
    event_router = {
      topic_key             = "wf_events"
      name                  = "${var.app_name}-event-router-push"
      push_endpoint         = local.event_router_push
      enable_subscriber_iam = false
      ack_deadline_seconds  = 30
    }
  }
}

module "migrate" {
  count                 = var.has_database ? 1 : 0
  source                = "../../../modules/cloudrun-migrate-job"
  name                  = "${var.app_name}-migrate"
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  service_account_email = google_service_account.runtime.email
  labels                = var.labels
  execute               = false
  args                  = var.migrate_args
  env = {
    LOG_LEVEL                    = "INFO"
    EVENTS_QUEUE_URL             = "mem://frame.events.migrate"
    OTEL_TRACES_EXPORTER         = "none"
    OTEL_METRICS_EXPORTER        = "none"
    OTEL_LOGS_EXPORTER           = "none"
    PERMISSIONS_REGISTRATION_URL = "${local.api_base}/tenancy/_internal/register/permissions"
  }
  secret_env = {
    DATABASE_URL = { secret = module.secrets.secret_ids[local.database_direct_secret_id] }
  }
  depends_on = [module.secrets, module.db]
}

module "service" {
  source                = "../../../modules/cloudrun-service"
  name                  = var.app_name
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  labels                = var.labels
  service_account_email = google_service_account.runtime.email
  container_port        = var.container_port
  use_http2             = true
  memory                = var.memory
  # Keep ≥1 so mem:// scheduler wake queues and in-process timers stay live.
  min_instance_count = 1
  public_invoker     = true
  env = merge(
    module.edge.service_env,
    # Multi-topic Pub/Sub: events dual-URL + FRAME_QUEUE_PUSH_OIDC_* from module.
    module.messaging.service_env,
    local.app_env,
  )
  secret_env = merge(
    var.has_database ? {
      DATABASE_URL         = { secret = module.secrets.secret_ids[local.database_secret_id] }
      REPLICA_DATABASE_URL = { secret = module.secrets.secret_ids[local.database_secret_id] }
    } : {},
    {
      OAUTH2_SIGNER_API_KEY = { secret = "hydra-webhook-psk" }
    },
  )
  depends_on = [
    module.secrets,
    module.messaging,
    module.db,
    module.migrate,
  ]
}

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
