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
  value = local.events_topic_name
}

output "events_subscription_name" {
  value = local.events_sub_name
}

output "events_ref" {
  description = "Frame queue reference / push demux key"
  value       = local.events_ref
}

output "frame_publish_url" {
  description = "gcppubsub:// publish URL for EVENTS_QUEUE_PUBLISH_URL"
  value       = local.frame_publish_url
}

output "frame_subscribe_url" {
  description = "push:// or gcppubsub:// subscribe URL for EVENTS_QUEUE_SUBSCRIBE_URL"
  value       = local.frame_subscribe_url
}

output "frame_push_handler_path" {
  description = "Path Pub/Sub push must target"
  value       = local.events_ref != "" ? "/_frame/queue/${local.events_ref}" : ""
}

output "service_env" {
  description = "Env for Cloud Run Frame services (gcppubsub publish + push subscribe + OIDC)"
  value = merge(
    { for k, t in google_pubsub_topic.this : "PUBSUB_TOPIC_${upper(replace(k, "-", "_"))}" => t.name },
    { for k, s in google_pubsub_subscription.this : "PUBSUB_SUBSCRIPTION_${upper(replace(k, "-", "_"))}" => s.name },
    {
      MESSAGING_BACKEND = "pubsub"
    },
    local.events_topic_name != "" ? {
      EVENTS_QUEUE_NAME = local.events_ref
      # Dual-URL pattern (Frame ≥2.0.10). Fallback EVENTS_QUEUE_URL kept for older Frame.
      EVENTS_QUEUE_URL           = local.frame_publish_url
      EVENTS_QUEUE_PUBLISH_URL   = local.frame_publish_url
      EVENTS_QUEUE_SUBSCRIBE_URL = local.frame_subscribe_url
      FRAME_QUEUE_PUSH_BASE_PATH = "/_frame/queue"
    } : {},
    # Always emit the full FRAME_QUEUE_PUSH_OIDC_* suite when push+OIDC is enabled.
    # Frame validates: signature (JWKS) + issuer + audience + allowed email/sub.
    local.push_oidc_enabled ? {
      FRAME_QUEUE_PUSH_AUTH                = "oidc"
      FRAME_QUEUE_PUSH_REQUIRE_AUTH        = "true"
      FRAME_QUEUE_PUSH_OIDC_AUDIENCE       = local.push_oidc_audience
      FRAME_QUEUE_PUSH_OIDC_ISSUERS        = local.push_oidc_issuers
      FRAME_QUEUE_PUSH_OIDC_JWKS_URL       = local.push_oidc_jwks_url
      FRAME_QUEUE_PUSH_OIDC_ALLOWED_EMAILS = var.push_oidc_service_account_email
      } : (
      # Pull-only / non-Frame: leave push auth unset (Frame defaults to none).
      local.events_topic_name != "" && !local.default_is_push ? {
        FRAME_QUEUE_PUSH_AUTH = "none"
      } : {}
    ),
  )
}

output "frame_push_oidc" {
  description = "Resolved Frame push OIDC settings (for debugging / docs)"
  value = local.push_oidc_enabled ? {
    auth           = "oidc"
    audience       = local.push_oidc_audience
    issuers        = local.push_oidc_issuers
    jwks_url       = local.push_oidc_jwks_url
    allowed_emails = var.push_oidc_service_account_email
  } : null
}
