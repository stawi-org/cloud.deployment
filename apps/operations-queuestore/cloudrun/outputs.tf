output "service_uri" {
  value = module.service.uri
}

output "project_id" {
  value = var.project_id
}

output "neon_project_id" {
  value = try(module.db[0].project_id, null)
}

output "neon_extensions" {
  value = try(module.db[0].extensions, [])
}

output "database_secret_id" {
  value = try(module.secrets.secret_ids["${var.app_name}-database-url"], null)
}

output "runtime_service_account_email" {
  value = google_service_account.runtime.email
}

output "pubsub_topic_names" {
  value = module.messaging.topic_names
}
