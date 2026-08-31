# operations-trustage — Frame Cloud Run via modules/frame-cloudrun-app.
# Multi-topic Pub/Sub (events / exec / wf-events) + min_instance_count=1.

provider "neon" {
  api_key = var.neon_api_key
}

provider "supabase" {
  access_token = var.supabase_access_token
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  service_run_url      = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  events_ref           = "${var.app_name}-events"
  exec_topic_name      = "${var.app_name}-exec"
  wf_events_topic_name = "${var.app_name}-wf-events"
  exec_worker_ref      = "exec-worker"
  event_router_ref     = "event-router"
  push_oidc_audience   = local.service_run_url
}

# Supabase project (phase 1 of the migration). Base five extensions match the
# Neon defaults now that timescaledb is gone.
module "supabase_db" {
  count  = var.supabase_enabled ? 1 : 0
  source = "../../../modules/supabase-database"

  app_name = var.app_name
  org_id   = var.supabase_org_id
  region   = var.supabase_region
  extensions = [
    "uuid-ossp",
    "pg_stat_statements",
    "pg_trgm",
    "btree_gin",
    "btree_gist",
  ]
}

locals {
  # Phase-1 staging secrets: expose the Supabase URIs for the data copy
  # before cutover. Removed once the migration completes.
  supabase_secret_ids = var.supabase_enabled ? [
    "${var.app_name}-supabase-database-url",
    "${var.app_name}-supabase-database-url-direct",
  ] : []
  supabase_secret_values = var.supabase_enabled ? {
    "${var.app_name}-supabase-database-url"        = module.supabase_db[0].pooled_connection_uri
    "${var.app_name}-supabase-database-url-direct" = module.supabase_db[0].connection_uri
  } : {}
}

module "frame" {
  source = "../../../modules/frame-cloudrun-app"

  app_name   = var.app_name
  project_id = var.project_id
  region     = var.region
  platform   = var.platform
  image      = var.image
  labels     = var.labels

  identity_project_id = var.identity_project_id
  identity_region     = var.identity_region

  neon_org_id              = var.neon_org_id
  neon_region_id           = var.neon_region_id
  neon_extensions          = var.neon_extensions
  has_database             = var.has_database

  # Supabase migration: staging secrets in phase 1; live-secret override in
  # phase 2 (after the data copy). Neon stays provisioned for rollback.
  extra_secret_ids    = toset(concat(tolist(var.extra_secret_ids), local.supabase_secret_ids))
  extra_version_ids   = toset(concat(tolist(var.extra_version_ids), local.supabase_secret_ids))
  extra_secret_values = merge(var.extra_secret_values, local.supabase_secret_values)
  database_url_override = (
    var.database_cutover && var.supabase_enabled
    ? module.supabase_db[0].pooled_connection_uri
    : null
  )
  database_url_direct_override = (
    var.database_cutover && var.supabase_enabled
    ? module.supabase_db[0].connection_uri
    : null
  )
  container_port           = var.container_port
  memory                   = var.memory
  migrate_args             = var.migrate_args
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  # Greenfield Hydra client id is "trustage" (not service-trustage).
  oauth2_service_client_id = "trustage"

  min_instance_count = 1
  push_oidc_audience = local.push_oidc_audience

  create_default_events_topic = false
  messaging_topics = {
    events    = { name = local.events_ref }
    exec      = { name = local.exec_topic_name }
    wf_events = { name = local.wf_events_topic_name }
  }
  messaging_subscriptions = {
    events = {
      topic_key             = "events"
      name                  = "${local.events_ref}-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${local.events_ref}"
      enable_subscriber_iam = false
    }
    exec_worker = {
      topic_key             = "exec"
      name                  = "${var.app_name}-exec-worker-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${local.exec_worker_ref}"
      enable_subscriber_iam = false
      ack_deadline_seconds  = 60
    }
    event_router = {
      topic_key             = "wf_events"
      name                  = "${var.app_name}-event-router-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${local.event_router_ref}"
      enable_subscriber_iam = false
      ack_deadline_seconds  = 30
    }
  }

  # Colony operations-trustage.yaml queue/tuning envs → Pub/Sub dual-URL shape.
  service_env_extra = {
    CACHE_REQUIRE_VALKEY           = "false"
    QUEUE_EXEC_DISPATCH_NAME       = "exec-dispatch"
    QUEUE_EXEC_DISPATCH_URL        = "gcppubsub://${var.project_id}/${local.exec_topic_name}"
    QUEUE_EXEC_WORKER_NAME         = local.exec_worker_ref
    QUEUE_EXEC_WORKER_URL          = "push://${local.exec_worker_ref}?protocol=gcppubsub"
    QUEUE_EVENT_INGEST_NAME        = "event-ingest"
    QUEUE_EVENT_INGEST_URL         = "gcppubsub://${var.project_id}/${local.wf_events_topic_name}"
    QUEUE_EVENT_ROUTER_NAME        = local.event_router_ref
    QUEUE_EVENT_ROUTER_URL         = "push://${local.event_router_ref}?protocol=gcppubsub"
    EXEC_WORKER_MAX_ACK_PENDING    = "0"
    EVENT_ROUTER_MAX_ACK_PENDING   = "0"
    EVENT_ROUTER_BINDING_LIMIT     = "200"
    OUTBOX_BATCH_SIZE              = "20"
    OUTBOX_MAX_BATCHES_PER_SWEEP   = "50"
    DISPATCH_BATCH_SIZE            = "50"
    DISPATCH_MAX_BATCHES_PER_SWEEP = "50"
    ADAPTER_HTTP_TIMEOUT_SECONDS   = "30"
    DATABASE_POOL_MAX_CONNS        = "50"
    WORKFLOW_ROW_RETENTION_HOURS   = "720"
  }

  app_env = {}
}
