# payment-payment — Frame Cloud Run (owns shared integrator Pub/Sub topics).

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

data "google_secret_manager_secret_version" "identity_hydra_psk" {
  project = var.identity_project_id
  secret  = "hydra-webhook-psk"
  version = "latest"
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
  # payment-polar-payments is the PAYMENT_LINK target (same naming as other rails).
  polar_payments_topic = "payment-polar-payments"
  prompt_route_uris = merge(
    { for k, topic in local.prompt_topics : k => "gcppubsub://${var.project_id}/${topic}" },
    { "m-pesa" = "gcppubsub://${var.project_id}/${local.prompt_topics["mpesa"]}" },
  )
  generated_secret_ids = toset(["hydra-webhook-psk"])
  generated_secret_values = {
    "hydra-webhook-psk" = data.google_secret_manager_secret_version.identity_hydra_psk.secret_data
  }
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

  neon_org_id              = var.neon_org_id
  neon_region_id           = var.neon_region_id
  neon_extensions          = var.neon_extensions
  has_database             = var.has_database
  container_port           = var.container_port
  memory                   = var.memory
  migrate_args             = var.migrate_args
  resource_path            = var.resource_path
  requested_audience_paths = var.requested_audience_paths
  oauth2_service_client_id = "service-payment"

  extra_secret_ids            = local.generated_secret_ids
  extra_version_ids           = local.generated_secret_ids
  extra_secret_values         = local.generated_secret_values
  grant_oauth_signer_accessor = false

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

  depends_on = [
    google_pubsub_topic.prompt,
    google_pubsub_topic.rail_payments,
  ]
}

resource "google_pubsub_topic_iam_member" "publish_prompt" {
  for_each = local.prompt_topics
  project  = var.project_id
  topic    = google_pubsub_topic.prompt[each.key].name
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${module.frame.runtime_service_account_email}"
}

resource "google_pubsub_topic_iam_member" "publish_polar_payments" {
  project = var.project_id
  topic   = google_pubsub_topic.rail_payments["polar"].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.frame.runtime_service_account_email}"
}
