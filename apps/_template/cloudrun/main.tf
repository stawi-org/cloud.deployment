# Repeatable Cloud Run + Neon + Pub/Sub app root.
# Account selection (which GCP project / Neon org) is OUTSIDE this file:
#   app.yaml → config/gcp-accounts.yaml + config/neon-accounts.yaml → CI vars.
#
# Secrets that must not live in git:
#   - neon_api_key (deploy-time provider) from SOPS credentials (CI)
#   - DATABASE_URL and extra secrets in GCP Secret Manager for runtime
#
# Frame messaging (v2.0.10+):
#   publish  → gcppubsub://{project}/{app}-events
#   receive  → push://{app}-events  (GCP POST /_frame/queue/{app}-events)

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
  # Deterministic Cloud Run URL for Pub/Sub push (stable before first deploy).
  service_run_url      = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  events_ref           = "${var.app_name}-events"
  events_push_endpoint = "${local.service_run_url}/_frame/queue/${local.events_ref}"

  # Pooled for runtime; direct for migrations (Frame advisory locks need a real session).
  database_secret_id        = "${var.app_name}-database-url"
  database_direct_secret_id = "${var.app_name}-database-url-direct"
  secret_ids = setunion(
    toset([local.database_secret_id, local.database_direct_secret_id]),
    var.extra_secret_ids,
  )
  version_ids = toset([local.database_secret_id, local.database_direct_secret_id])
  secret_values = merge(
    { (local.database_secret_id) = module.db.pooled_connection_uri },
    { (local.database_direct_secret_id) = module.db.connection_uri },
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

# Frame default: `migrate` subcommand (override per app for Hydra/Keto).
module "migrate" {
  source = "../../../modules/cloudrun-migrate-job"

  name                  = "${var.app_name}-migrate"
  project_id            = var.project_id
  region                = var.region
  image                 = var.image
  service_account_email = google_service_account.runtime.email
  labels                = var.labels
  args                  = ["migrate"]
  env = {
    LOG_LEVEL             = "INFO"
    EVENTS_QUEUE_URL      = "mem://frame.events.migrate"
    OTEL_TRACES_EXPORTER  = "none"
    OTEL_METRICS_EXPORTER = "none"
    OTEL_LOGS_EXPORTER    = "none"
  }
  secret_env = {
    DATABASE_URL = {
      secret = module.secrets.secret_ids[local.database_direct_secret_id]
    }
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
  }

  depends_on = [
    module.secrets,
    module.messaging,
    module.migrate,
  ]
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
