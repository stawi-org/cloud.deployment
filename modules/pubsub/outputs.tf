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

# Frame dual-mode self-events (publish + subscribe + WithRegisterEvents handlers).
# App-scoped mem URL — not the Frame default frame.events.internal_._queue name.
output "frame_events_queue_url" {
  description = "Frame EVENTS_QUEUE_URL for dual publish/subscribe (mem://, handlers)"
  value       = local.events_topic_name != "" ? "mem://${local.events_topic_name}" : ""
}

output "frame_events_queue_name" {
  description = "Frame EVENTS_QUEUE_NAME (reference for handlers / push demux)"
  value       = local.events_topic_name
}

# Frame push-mode subscriber URL (DeliveryModePush → /_frame/queue/{ref}).
output "frame_push_queue_url" {
  description = "Frame EVENTS_QUEUE_URL for push-only receive (push://{ref})"
  value       = local.events_topic_name != "" ? "push://${local.events_topic_name}" : ""
}

output "frame_push_handler_path" {
  description = "HTTP path Pub/Sub should push to for this app's events ref"
  value       = local.events_topic_name != "" ? "/_frame/queue/${local.events_topic_name}" : ""
}

output "service_env" {
  description = "Env vars for Cloud Run Frame apps (handler path, not gcppubsub scheme)"
  value = merge(
    { for k, t in google_pubsub_topic.this : "PUBSUB_TOPIC_${upper(replace(k, "-", "_"))}" => t.name },
    { for k, s in google_pubsub_subscription.this : "PUBSUB_SUBSCRIPTION_${upper(replace(k, "-", "_"))}" => s.name },
    {
      MESSAGING_BACKEND = "pubsub"
    },
    # Dual-mode mem:// so Frame setupEventsQueue can both publish and dispatch
    # to WithRegisterEvents handlers. Name is app-scoped (not frame default).
    local.events_topic_name != "" ? {
      EVENTS_QUEUE_URL  = "mem://${local.events_topic_name}"
      EVENTS_QUEUE_NAME = local.events_topic_name
    } : {},
  )
}
