output "service_name" {
  value = module.service.name
}

output "service_uri" {
  value = module.service.uri
}

output "service_run_url" {
  description = "Deterministic *.run.app URL used for Pub/Sub push"
  value       = local.service_run_url
}

output "runtime_service_account_email" {
  value = google_service_account.runtime.email
}

output "runtime_service_account_name" {
  value = google_service_account.runtime.name
}

output "api_base" {
  value = local.api_base
}

output "oauth2_origin" {
  value = local.oauth2_origin
}

output "resource_path" {
  value = local.resource_path
}

output "events_ref" {
  value = local.events_ref
}

output "events_push_endpoint" {
  value = local.events_push_endpoint
}

output "database_secret_id" {
  value = var.has_database ? local.database_secret_id : null
}

output "database_direct_secret_id" {
  value = var.has_database ? local.database_direct_secret_id : null
}

output "secret_ids" {
  value = module.secrets.secret_ids
}

output "pubsub_topic_names" {
  value = var.enable_messaging ? module.messaging[0].topic_names : {}
}

output "pubsub_subscription_names" {
  value = var.enable_messaging ? module.messaging[0].subscription_names : {}
}

output "frame_publish_url" {
  value = var.enable_messaging ? module.messaging[0].frame_publish_url : ""
}

output "frame_subscribe_url" {
  value = var.enable_messaging ? module.messaging[0].frame_subscribe_url : ""
}

output "neon_project_id" {
  value = var.has_database && var.neon_enabled ? module.db[0].project_id : null
}

output "migrate_job_name" {
  value = var.has_database ? module.migrate[0].name : null
}
