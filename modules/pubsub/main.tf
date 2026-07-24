# Google Cloud Pub/Sub is the only messaging plane for apps in cloud.deployment.
# Cluster NATS/JetStream must not be wired into Cloud Run apps.

locals {
  default_topic_key = "events"

  # Effective topics: explicit map, or default single events topic
  topics = length(var.topics) > 0 ? var.topics : (
    var.create_default_events_topic ? {
      (local.default_topic_key) = {
        name                       = "${var.app_name}-events"
        message_retention_duration = "604800s"
      }
    } : {}
  )

  subscriptions = length(var.subscriptions) > 0 ? var.subscriptions : (
    contains(keys(local.topics), local.default_topic_key) ? {
      (local.default_topic_key) = {
        topic_key                  = local.default_topic_key
        name                       = "${var.app_name}-events-pull"
        ack_deadline_seconds       = 20
        message_retention_duration = "604800s"
        push_endpoint              = null
        enable_subscriber_iam      = true
      }
    } : {}
  )
}

resource "google_pubsub_topic" "this" {
  for_each = local.topics

  project = var.project_id
  name    = coalesce(each.value.name, "${var.app_name}-${each.key}")
  labels  = var.labels

  message_retention_duration = each.value.message_retention_duration
}

resource "google_pubsub_subscription" "this" {
  for_each = local.subscriptions

  project = var.project_id
  name    = coalesce(each.value.name, "${var.app_name}-${each.key}")
  topic   = google_pubsub_topic.this[each.value.topic_key].id
  labels  = var.labels

  ack_deadline_seconds       = each.value.ack_deadline_seconds
  message_retention_duration = each.value.message_retention_duration

  dynamic "push_config" {
    for_each = each.value.push_endpoint != null && each.value.push_endpoint != "" ? [1] : []
    content {
      push_endpoint = each.value.push_endpoint
    }
  }

  depends_on = [google_pubsub_topic.this]
}

resource "google_pubsub_topic_iam_member" "publisher" {
  for_each = var.enable_publisher_iam ? local.topics : {}

  project = var.project_id
  topic   = google_pubsub_topic.this[each.key].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.runtime_service_account_email}"
}

resource "google_pubsub_subscription_iam_member" "subscriber" {
  for_each = {
    for k, s in local.subscriptions : k => s
    if s.enable_subscriber_iam
  }

  project      = var.project_id
  subscription = google_pubsub_subscription.this[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.runtime_service_account_email}"
}
