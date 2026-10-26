# Seed USSD inbound: completed borrower USSD sessions.
#
# The USSD engine hands a completed session to the notification service,
# whose receive route for "ussd" publishes it here
# (gcppubsub://stawi-finance/finance-seed-ussd-inbound). Seed consumes it on
# push at /_frame/queue/seed-ussd-inbound (SEED_USSD_INBOUND_URI).
# Kept beside the module so the module's default events topic is untouched.

data "google_project" "seed" {
  project_id = var.project_id
}

locals {
  seed_run_url       = "https://${var.app_name}-${data.google_project.seed.number}.${var.region}.run.app"
  ussd_inbound_ref   = "seed-ussd-inbound"
  ussd_inbound_push  = "${local.seed_run_url}/_frame/queue/${local.ussd_inbound_ref}"
  notification_agent = "serviceAccount:communications-notification@stawi-communications.iam.gserviceaccount.com"
}

resource "google_pubsub_topic" "ussd_inbound" {
  project                    = var.project_id
  name                       = "${var.app_name}-ussd-inbound"
  labels                     = var.labels
  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "ussd_inbound_dlq" {
  project = var.project_id
  name    = "${var.app_name}-ussd-inbound-dlq"
  labels  = var.labels
}

# Only the notification service publishes completed sessions.
resource "google_pubsub_topic_iam_member" "ussd_inbound_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.ussd_inbound.name
  role    = "roles/pubsub.publisher"
  member  = local.notification_agent
}

resource "google_pubsub_subscription" "ussd_inbound_push" {
  project              = var.project_id
  name                 = "${var.app_name}-ussd-inbound-push"
  topic                = google_pubsub_topic.ussd_inbound.id
  labels               = var.labels
  ack_deadline_seconds = 60

  push_config {
    push_endpoint = local.ussd_inbound_push
    oidc_token {
      service_account_email = module.frame.runtime_service_account_email
      audience              = local.ussd_inbound_push
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.ussd_inbound_dlq.id
    max_delivery_attempts = 10
  }
}

# Pub/Sub's service agent moves undeliverable messages to the DLQ.
resource "google_pubsub_topic_iam_member" "ussd_inbound_dlq_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.ussd_inbound_dlq.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.seed.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "ussd_inbound_dlq_subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.ussd_inbound_push.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.seed.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Seed's USSD secrets live outside tofu (created with their values by ops, so
# a revision never references a secret without a version):
#   finance-seed-ussd-secret-key       X25519 private key (base64); the engine
#                                      seals PINs with its public half
#   finance-seed-ussd-gateway-auth-key the secret in the Africa's Talking
#                                      callback URL (?authKey=)
locals {
  ussd_secrets = toset(["${var.app_name}-ussd-secret-key", "${var.app_name}-ussd-gateway-auth-key"])
}

resource "google_secret_manager_secret_iam_member" "ussd" {
  for_each  = local.ussd_secrets
  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.frame.runtime_service_account_email}"
}
