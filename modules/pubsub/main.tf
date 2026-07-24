# Regional Cloud Pub/Sub for Cloud Run Frame apps.
#
# Pattern (Frame v2.0.10+):
#   publish  → gcppubsub://{project}/{topic}     (OpenTopic)
#   receive  → push://{ref}                      (HTTP demux)
#   GCP push → POST https://{service}/_frame/queue/{ref}
#
# message_storage_policy keeps messages in the app region (no cross-continent storage).

locals {
  default_topic_key   = "events"
  default_events_name = "${var.app_name}-events"
  events_ref          = local.default_events_name

  # Prefer explicit list; otherwise pin storage to the workload region only.
  persistence_regions = length(var.allowed_persistence_regions) > 0 ? var.allowed_persistence_regions : (
    var.region != "" ? [var.region] : []
  )

  topics = length(var.topics) > 0 ? var.topics : (
    var.create_default_events_topic ? {
      (local.default_topic_key) = {
        name                       = local.default_events_name
        message_retention_duration = "604800s"
      }
    } : {}
  )

  # Default: push subscription to Frame handler when push endpoint is known;
  # otherwise a pull subscription for non-Frame producers (Hydra/Keto/etc).
  default_is_push = var.default_push_endpoint != null && var.default_push_endpoint != ""
  subscriptions = length(var.subscriptions) > 0 ? var.subscriptions : (
    contains(keys(local.topics), local.default_topic_key) ? {
      (local.default_topic_key) = {
        topic_key                  = local.default_topic_key
        name                       = local.default_is_push ? "${local.default_events_name}-push" : local.default_events_name
        ack_deadline_seconds       = 30
        message_retention_duration = "604800s"
        push_endpoint              = var.default_push_endpoint
        # Pull consumers need subscriber IAM; push delivery is Pub/Sub → Cloud Run.
        enable_subscriber_iam = !local.default_is_push
      }
    } : {}
  )

  events_topic_name = try(google_pubsub_topic.this[local.default_topic_key].name, "")
  events_sub_name   = try(google_pubsub_subscription.this[local.default_topic_key].name, "")

  # Frame publish/subscribe URLs (dual when push endpoint is set).
  frame_publish_url = local.events_topic_name != "" ? (
    "gcppubsub://${var.project_id}/${local.events_topic_name}"
  ) : ""
  frame_subscribe_url = local.events_topic_name != "" ? (
    var.default_push_endpoint != null && var.default_push_endpoint != ""
    ? "push://${local.events_ref}?protocol=gcppubsub"
    : "gcppubsub://${var.project_id}/${local.events_sub_name}"
  ) : ""
}

resource "google_pubsub_topic" "this" {
  for_each = local.topics

  project = var.project_id
  name    = coalesce(each.value.name, "${var.app_name}-${each.key}")
  labels  = var.labels

  message_retention_duration = each.value.message_retention_duration

  # Keep storage in the workload region (e.g. europe-west9) — avoid multi-continent hops.
  dynamic "message_storage_policy" {
    for_each = length(local.persistence_regions) > 0 ? [1] : []
    content {
      allowed_persistence_regions = local.persistence_regions
      enforce_in_transit          = var.enforce_in_transit
    }
  }
}

# Optional DLQ for failed push deliveries.
resource "google_pubsub_topic" "dlq" {
  count = var.create_dead_letter_topic && local.events_topic_name != "" ? 1 : 0

  project = var.project_id
  name    = "${local.default_events_name}-dlq"
  labels  = var.labels

  dynamic "message_storage_policy" {
    for_each = length(local.persistence_regions) > 0 ? [1] : []
    content {
      allowed_persistence_regions = local.persistence_regions
      enforce_in_transit          = var.enforce_in_transit
    }
  }
}

resource "google_pubsub_subscription" "this" {
  for_each = local.subscriptions

  project = var.project_id
  name    = coalesce(each.value.name, "${var.app_name}-${each.key}")
  topic   = google_pubsub_topic.this[each.value.topic_key].id
  labels  = var.labels

  ack_deadline_seconds       = each.value.ack_deadline_seconds
  message_retention_duration = each.value.message_retention_duration
  # Prefer regional endpoints when clients support them.
  enable_message_ordering = false

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

      attributes = {
        x-goog-version = "v1"
      }
    }
  }

  dynamic "dead_letter_policy" {
    for_each = length(google_pubsub_topic.dlq) > 0 ? [1] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dlq[0].id
      max_delivery_attempts = var.dead_letter_max_delivery_attempts
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
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

# Pub/Sub service agent needs publisher on DLQ and subscriber on source subs
# when dead letter is enabled (required for delivery-attempt forwarding).
resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  count = length(google_pubsub_topic.dlq) > 0 && var.pubsub_service_agent_email != "" ? 1 : 0

  project = var.project_id
  topic   = google_pubsub_topic.dlq[0].name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.pubsub_service_agent_email}"
}

resource "google_pubsub_subscription_iam_member" "dlq_subscriber" {
  for_each = length(google_pubsub_topic.dlq) > 0 && var.pubsub_service_agent_email != "" ? local.subscriptions : {}

  project      = var.project_id
  subscription = google_pubsub_subscription.this[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.pubsub_service_agent_email}"
}
