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

output "service_env" {
  description = "Env vars to inject into Cloud Run (topic/subscription names)"
  value = merge(
    { for k, t in google_pubsub_topic.this : "PUBSUB_TOPIC_${upper(replace(k, "-", "_"))}" => t.name },
    { for k, s in google_pubsub_subscription.this : "PUBSUB_SUBSCRIPTION_${upper(replace(k, "-", "_"))}" => s.name },
    {
      MESSAGING_BACKEND = "pubsub"
    }
  )
}
