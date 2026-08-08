# opportunities-matching — owns Neon product DB + product Pub/Sub topics.
# Crawl pipeline remains on cluster. hydra-webhook-psk seeded OOB into
# stawi-opportunities (copy of identity).

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

locals {
  service_run_url    = "https://${var.app_name}-${data.google_project.this.number}.${var.region}.run.app"
  push_oidc_audience = local.service_run_url

  # Product async via GCP Pub/Sub (cluster worker + Cloud Run matching).
  fanout_topic        = "opportunities-fanout"
  cv_embed_topic      = "opportunities-cv-embed"
  worker_embed_topic  = "opportunities-worker-embed"
  worker_embed_sub    = "opportunities-worker-embed-pull"
  events_ref          = "${var.app_name}-events"
  # OCI cluster worker SA (JSON key in k8s secret gcp-sa-opportunities-worker).
  cluster_worker_sa   = "opportunities-cluster-worker@${var.project_id}.iam.gserviceaccount.com"
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
  container_port           = var.container_port
  memory                   = var.memory
  cpu                      = "1"
  # Frame setup plan: module sets DO_SETUP=true + default args ["setup"].
  # MIGRATION_PATH is app-specific for the registered migrate step.
  migrate_args = ["setup"]
  migrate_env = {
    MIGRATION_PATH = "/migrations/0001"
  }
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  # Hydra internal client_id from service-authentication greenfield seed.
  oauth2_service_client_id = "opportunities-matching"

  grant_oauth_signer_accessor = true
  push_oidc_audience          = local.push_oidc_audience
  use_http2                   = true
  permissions_registration    = false
  # Frame serves /readyz (readiness) and /livez (liveness). /healthz returns
  # Google Frontend HTML 404 on h2c Cloud Run for several Frame services.
  startup_probe_path          = "/readyz"
  liveness_probe_path         = "/livez"

  # Default {app}-events plus product fan-out / CV embed / worker-embed topics.
  create_default_events_topic = true
  messaging_topics = {
    fanout       = { name = local.fanout_topic }
    cv_embed     = { name = local.cv_embed_topic }
    worker_embed = { name = local.worker_embed_topic }
  }
  messaging_subscriptions = {
    fanout = {
      topic_key             = "fanout"
      name                  = "${local.fanout_topic}-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${local.fanout_topic}"
      enable_subscriber_iam = false
      ack_deadline_seconds  = 300
    }
    cv_embed = {
      topic_key             = "cv_embed"
      name                  = "${local.cv_embed_topic}-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${local.cv_embed_topic}"
      enable_subscriber_iam = false
      ack_deadline_seconds  = 300
    }
    # Cluster worker pull subscription (OCI has no Workload Identity).
    worker_embed = {
      topic_key             = "worker_embed"
      name                  = local.worker_embed_sub
      enable_subscriber_iam = true
      ack_deadline_seconds  = 300
    }
  }

  # Pre-seeded SM secrets (do not create via tofu — values already seeded OOB).
  # hydra-webhook-psk is the default oauth_signer_secret (frame grants accessor).
  secret_env_extra = {
    BILLING_WEBHOOK_SECRET  = { secret = "billing-webhook-secret" }
    CHECKOUT_INTERNAL_TOKEN = { secret = "checkout-internal-token" }
    # Shared with platform chat-agent (comma-separated keys; matching uses first).
    # Required for sync AI CV sectioning on upload.
    INFERENCE_API_KEY = { secret = "platform-chat-agent-inference-api-keys" }
  }

  service_env_extra = {
    # Path A fan-out (worker → this topic → matching consumer).
    OPPORTUNITY_FANOUT_QUEUE_URI  = "push://${local.fanout_topic}?protocol=gcppubsub"
    OPPORTUNITY_FANOUT_QUEUE_NAME = local.fanout_topic
    MATCHING_FANOUT_ENABLED       = "true"
    # CV embed stage (self-push).
    CV_EMBED_QUEUE_URL  = "push://${local.cv_embed_topic}?protocol=gcppubsub"
    CV_EMBED_QUEUE_NAME = local.cv_embed_topic
    # Cluster worker URIs (document for product-opportunities Helm).
    MATCHING_FANOUT_PUBLISH_URL     = "gcppubsub://${var.project_id}/${local.fanout_topic}"
    WORKER_EMBED_PUBLISH_URL        = "gcppubsub://${var.project_id}/${local.worker_embed_topic}"
    WORKER_EMBED_SUBSCRIBE_URL      = "gcppubsub://${var.project_id}/${local.worker_embed_sub}"
  }

  app_env = {
    # Reuse existing Stawi services — no duplicated responsibilities.
    PROFILE_SERVICE_URI      = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI      = "https://api.stawi.org/tenancy"
    FILE_SERVICE_URI         = "https://api.stawi.org/files"
    REDIRECT_SERVICE_URI     = "https://api.stawi.org/redirect"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    BILLING_SERVICE_URI      = "https://api.stawi.org/payment"
    CHECKOUT_SERVICE_URI     = "https://api.stawi.org/checkout"
    CHECKOUT_PUBLIC_BASE_URL = "https://pay.stawi.org"
    PUBLIC_SITE_URL          = "https://opportunities.stawi.org"
    MATCHING_MIN_SCORE       = "0.45"
    SECURELY_RUN_SERVICE     = "true"
    # Platform chat-agent: structured intake + opportunity side-chat.
    CHAT_AGENT_SERVICE_URI   = "https://api.stawi.org/chat-agent"
    CHAT_AGENT_ENABLED       = "true"
    # Sync AI CV sectioning on upload (required before fully_processed).
    INFERENCE_PROVIDER = "google"
    INFERENCE_MODEL    = "gemini-3.6-flash"
  }
}

# Accessor IAM for pre-seeded secrets (not module-owned).
resource "google_secret_manager_secret_iam_member" "preseeded" {
  for_each = toset([
    "billing-webhook-secret",
    "checkout-internal-token",
    "platform-chat-agent-inference-api-keys",
  ])
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.frame.runtime_service_account_email}"
}

# Shared DB IAM for opportunities-api is granted from the API stack (SA exists
# after that apply). Apply order: matching → api.

# ---------------------------------------------------------------------------
# Cluster worker (OCI) — Pub/Sub for critical async path
# ---------------------------------------------------------------------------
# JSON key lives in k8s secret gcp-sa-opportunities-worker (key.json).
# Topics: fanout (publish only), worker-embed (publish + pull subscribe).

data "google_service_account" "cluster_worker" {
  account_id = "opportunities-cluster-worker"
  project    = var.project_id
}

resource "google_pubsub_topic_iam_member" "cluster_worker_fanout_publish" {
  project = var.project_id
  topic   = local.fanout_topic
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_service_account.cluster_worker.email}"
}

resource "google_pubsub_topic_iam_member" "cluster_worker_embed_publish" {
  project = var.project_id
  topic   = local.worker_embed_topic
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_service_account.cluster_worker.email}"
}

resource "google_pubsub_subscription_iam_member" "cluster_worker_embed_subscribe" {
  project      = var.project_id
  subscription = local.worker_embed_sub
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${data.google_service_account.cluster_worker.email}"
}
