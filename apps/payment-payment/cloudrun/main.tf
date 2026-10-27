# payment-payment — Frame Cloud Run (owns shared integrator Pub/Sub topics).
# hydra-webhook-psk seeded OOB into stawi-payments (copy of identity).

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
  prompt_topics = {
    mpesa       = "payment-mpesa-prompts"
    stripe      = "payment-stripe-prompts"
    polar       = "payment-polar-prompts"
    pawapay     = "payment-pawapay-prompts"
    flutterwave = "payment-flutterwave-prompts"
    jenga       = "payment-jenga-prompts"
    airtel      = "payment-airtel-prompts"
    mtn         = "payment-mtn-prompts"
  }
  polar_payments_topic = "payment-polar-payments"

  # Payment routes, written by the setup Job (PAYMENT_ROUTES). Each lending
  # partition receives into fintech operations and pays mobile numbers out
  # through M-Pesa; routes are chosen by partition, mode and contact kind.
  lending_partitions = {
    antinvestor = { tenant_id = "d6q1aekpf2taeg5iovp0", partition_id = "d6q1aekpf2taeg5iovpg", label = "Ant Investor" }
    stawi       = { tenant_id = "9bsv0s0hijjg02z5lbjg", partition_id = "9bsv0s0hijjg02qk7l1g", label = "Stawi" }
  }
  payment_routes = flatten([
    for key, p in local.lending_partitions : [
      {
        id           = "rx-fintech-operations-${key}"
        tenant_id    = p.tenant_id
        partition_id = p.partition_id
        name         = "Fintech operations"
        description  = "Payments received in ${p.label} go to fintech operations."
        route_type   = "any"
        mode         = "rx"
        uri          = "gcppubsub://stawi-finance/finance-operations-payment-received"
      },
      {
        id           = "tx-mpesa-msisdn-${key}"
        tenant_id    = p.tenant_id
        partition_id = p.partition_id
        name         = "M-Pesa payouts"
        description  = "Payments out of ${p.label} to a mobile number go through M-Pesa."
        route_type   = "msisdn"
        mode         = "tx"
        uri          = "gcppubsub://${var.project_id}/payment-mpesa-payments"
      },
    ]
  ])
  prompt_route_uris = merge(
    { for k, topic in local.prompt_topics : k => "gcppubsub://${var.project_id}/${topic}" },
    { "m-pesa" = "gcppubsub://${var.project_id}/${local.prompt_topics["mpesa"]}" },
  )
}

# Shared topics for rails (integrations attach push subscriptions only).
resource "google_pubsub_topic" "prompt" {
  for_each = local.prompt_topics
  project  = var.project_id
  name     = each.value
  labels   = var.labels
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_topic" "rail_payments" {
  for_each = local.prompt_topics
  project  = var.project_id
  name     = "payment-${each.key}-payments"
  labels   = var.labels
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
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

  neon_org_id     = var.neon_org_id
  neon_region_id  = var.neon_region_id
  neon_extensions = var.neon_extensions
  has_database    = var.has_database
  container_port  = var.container_port
  memory          = var.memory
  migrate_args    = var.migrate_args
  migrate_env = {
    PAYMENT_ROUTES = jsonencode(local.payment_routes)
  }
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-payment"

  grant_oauth_signer_accessor = true

  service_env_extra = {
    INITIATE_PROMPT_TOPIC_NAME = "mpesa-prompts"
    INITIATE_PROMPT_TOPIC_URI  = "gcppubsub://${var.project_id}/${local.prompt_topics["mpesa"]}"
    INITIATE_PROMPT_ROUTE_URIS = jsonencode(local.prompt_route_uris)
    PAYMENT_LINK_TOPIC_NAME    = "polar-payments"
    PAYMENT_LINK_TOPIC_URI     = "gcppubsub://${var.project_id}/${local.polar_payments_topic}"
  }

  app_env = {
    PROFILE_SERVICE_URI        = "https://api.stawi.org/profile"
    TENANCY_SERVICE_URI        = "https://api.stawi.org/tenancy"
    LEDGER_SERVICE_URI         = "https://api.stawi.org/ledger"
    PAYMENT_TRANSACTION_TOPIC  = "svc.payments.transaction"
    PAYMENT_CONFIRMATION_TOPIC = "svc.payments.confirmation"
    PAYMENT_FAILURE_TOPIC      = "svc.payments.failure"
    SECURELY_RUN_SERVICE       = "true"
  }
}

resource "google_pubsub_topic_iam_member" "publish_prompt" {
  for_each = local.prompt_topics
  project  = var.project_id
  topic    = google_pubsub_topic.prompt[each.key].name
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${module.frame.runtime_service_account_email}"
}

# Payouts: payment routes each payment out to its integration's payments
# topic (tx routes in the payment database, chosen by partition and the
# payee's contact kind).
resource "google_pubsub_topic_iam_member" "publish_rail_payments" {
  for_each = local.prompt_topics
  project  = var.project_id
  topic    = google_pubsub_topic.rail_payments[each.key].name
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${module.frame.runtime_service_account_email}"
}

resource "google_pubsub_topic_iam_member" "publish_polar_payments" {
  project = var.project_id
  topic   = google_pubsub_topic.rail_payments["polar"].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.frame.runtime_service_account_email}"
}
