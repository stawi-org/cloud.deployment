# Google Cloud Pub/Sub is the durable messaging plane for cloud.deployment.
# Cluster NATS/JetStream must not be wired into Cloud Run apps.
#
# Frame v2 queue schemes (frame/v2/docs/queue.md):
#   subscribe: mem:// | nats:// | push://{ref} | http(s)://…
#   publish:   mem:// | nats:// | ce+http(s)://… | cloudtasks://…
# There is no gcppubsub:// scheme in Frame. Self-events use mem:// (dual
# publish+subscribe) with WithRegisterEvents handlers. Durable ingress uses
# Pub/Sub push → POST /_frame/queue/{ref} when EVENTS_QUEUE_URL is push://
# (requires separate publish URL — see outputs and app docs).

locals {
  default_topic_key   = "events"
  default_events_name = "${var.app_name}-events"

  topics = length(var.topics) > 0 ? var.topics : (
    var.create_default_events_topic ? {
      (local.default_topic_key) = {
        name                       = local.default_events_name
        message_retention_duration = "604800s"
      }
    } : {}
  )

  # Prefer push to Frame handler when default_push_endpoint is set; else pull
  # for tooling. Subscription name matches topic for consistent naming.
  subscriptions = length(var.subscriptions) > 0 ? var.subscriptions : (
    contains(keys(local.topics), local.default_topic_key) ? {
      (local.default_topic_key) = {
        topic_key                  = local.default_topic_key
        name                       = local.default_events_name
        ack_deadline_seconds       = 20
        message_retention_duration = "604800s"
        push_endpoint              = var.default_push_endpoint
        enable_subscriber_iam      = var.default_push_endpoint == null || var.default_push_endpoint == ""
      }
    } : {}
  )

  events_topic_name = try(google_pubsub_topic.this[local.default_topic_key].name, "")
  events_sub_name   = try(google_pubsub_subscription.this[local.default_topic_key].name, "")
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

      dynamic "oidc_token" {
        for_each = var.push_oidc_service_account_email != "" ? [1] : []
        content {
          service_account_email = var.push_oidc_service_account_email
          audience              = var.push_oidc_audience != "" ? var.push_oidc_audience : each.value.push_endpoint
        }
      }
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
