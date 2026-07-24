output "topic_names" {
  description = "Map of logical topic key → topic name"
  value       = { for k, t in google_pubsub_topic.this : k => t.name }
}

output "topic_ids" {
  description = "Map of logical topic key → topic id"
  value       = { for k, t in google_pubsub_topic.this : k => t.id }
}

output "subscription_names" {
  description = "Map of logical subscription key → subscription name"
  value       = { for k, s in google_pubsub_subscription.this : k => s.name }
}

output "subscription_ids" {
  description = "Map of logical subscription key → subscription id"
  value       = { for k, s in google_pubsub_subscription.this : k => s.id }
}

output "events_topic_name" {
  description = "Default events topic name (empty if no default topic)"
  value       = local.events_topic_name
}

output "events_subscription_name" {
  description = "Default events subscription name (empty if none)"
  value       = local.events_sub_name
}

# Frame gocloud URL — same short name for topic and subscription so OpenTopic
# and OpenSubscription both resolve. Consume path: Frame WithRegisterEvents
# registers handlers; setupEventsQueue wires SubscribeWorker (not mem://).
output "events_queue_url" {
  description = "gcppubsub:// URL for Frame EVENTS_QUEUE_URL"
  value = local.events_topic_name != "" ? (
    "gcppubsub://${var.project_id}/${local.events_topic_name}"
  ) : ""
}

output "events_queue_name" {
  description = "Frame EVENTS_QUEUE_NAME (publisher/subscriber reference)"
  value       = local.events_topic_name
}

output "service_env" {
  description = "Env vars to inject into Cloud Run (Frame + generic Pub/Sub)"
  value = merge(
    { for k, t in google_pubsub_topic.this : "PUBSUB_TOPIC_${upper(replace(k, "-", "_"))}" => t.name },
    { for k, s in google_pubsub_subscription.this : "PUBSUB_SUBSCRIPTION_${upper(replace(k, "-", "_"))}" => s.name },
    {
      MESSAGING_BACKEND = "pubsub"
      GCP_PROJECT       = var.project_id
    },
    local.events_topic_name != "" ? {
      EVENTS_QUEUE_URL  = "gcppubsub://${var.project_id}/${local.events_topic_name}"
      EVENTS_QUEUE_NAME = local.events_topic_name
    } : {},
  )
}
