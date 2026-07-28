# communications-smtp — Frame Cloud Run via modules/frame-cloudrun-app.


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
  send_topic         = "notification-emailsmtp-send"
  send_ref           = "emailsmtp-send"
  push_oidc_audience = local.service_run_url
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
  migrate_args             = var.migrate_args
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-notification-emailsmtp"

  # Secret shells — seed values via scripts/sync-cluster-secrets-to-gcp.sh (not in git).
  extra_secret_ids  = toset([
    "smtp-server-access-key",
    "smtp-server-host",
    "smtp-server-port",
    "smtp-server-secret-key",
  ])
  extra_version_ids = toset([])
  secret_env_extra = {
    SMTP_SERVER_HOST = { secret = "smtp-server-host" }
    SMTP_SERVER_PORT = { secret = "smtp-server-port" }
    SMTP_SERVER_ACCESS_KEY = { secret = "smtp-server-access-key" }
    SMTP_SERVER_SECRET_KEY = { secret = "smtp-server-secret-key" }
  }
  create_default_events_topic = false
  push_oidc_audience          = local.push_oidc_audience

  messaging_topics = {
    events = { name = "${var.app_name}-events" }
    send   = { name = local.send_topic }
  }
  messaging_subscriptions = {
    events = {
      topic_key             = "events"
      name                  = "${var.app_name}-events-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${var.app_name}-events"
      enable_subscriber_iam = false
    }
    send = {
      topic_key             = "send"
      name                  = "${local.send_topic}-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${local.send_ref}"
      enable_subscriber_iam = false
    }
  }

  service_env_extra = {
    QUEUE_NOTIFICATION_EMAIL_DEQUEUE_NAME = local.send_ref
    QUEUE_NOTIFICATION_EMAIL_DEQUEUE_URI  = "push://${local.send_ref}?protocol=gcppubsub"
  }

  app_env = {
    PROFILE_SERVICE_URI = "https://api.stawi.org/profile"
    SETTINGS_SERVICE_URI = "https://api.stawi.org/settings"
    NOTIFICATION_SERVICE_URI = "https://api.stawi.org/notification"
    TENANCY_SERVICE_URI = "https://api.stawi.org/tenancy"
  }
}
