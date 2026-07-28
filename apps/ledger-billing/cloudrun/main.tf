# ledger-billing — Frame Cloud Run via modules/frame-cloudrun-app.


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
  lifecycle_topic    = "${var.app_name}-subscription-lifecycle"
  lifecycle_ref      = "subscription-lifecycle"
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
  oauth2_service_client_id = "service-billing"

  create_default_events_topic = false
  push_oidc_audience          = local.push_oidc_audience
  min_instance_count          = 1 # settlement sweep

  messaging_topics = {
    events    = { name = "${var.app_name}-events" }
    lifecycle = { name = local.lifecycle_topic }
  }
  messaging_subscriptions = {
    events = {
      topic_key             = "events"
      name                  = "${var.app_name}-events-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${var.app_name}-events"
      enable_subscriber_iam = false
    }
    lifecycle = {
      topic_key             = "lifecycle"
      name                  = "${local.lifecycle_topic}-push"
      push_endpoint         = "${local.service_run_url}/_frame/queue/${local.lifecycle_ref}"
      enable_subscriber_iam = false
    }
  }

  service_env_extra = {
    BILLING_SUBSCRIPTION_LIFECYCLE_TOPIC_URI = "gcppubsub://${var.project_id}/${local.lifecycle_topic}"
  }

  app_env = {
    TENANCY_SERVICE_URI = "https://api.stawi.org/tenancy"
    CHECKOUT_SERVICE_URI = "https://api.stawi.org/checkout"
    CHECKOUT_INVOICE_RETURN_URL = "https://admin.stawi.org/billing/payment/return"
    BILLING_SETTLEMENT_SWEEP_INTERVAL_SECONDS = "60"
    BILLING_SETTLEMENT_SWEEP_BATCH_SIZE = "50"
    BILLING_SUBSCRIPTION_LIFECYCLE_TOPIC_NAME = "subscription.lifecycle"
  }
}
