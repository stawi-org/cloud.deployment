output "service_uri" {
  value = module.service.uri
}

output "project_id" {
  value = var.project_id
}

output "neon_project_id" {
  value = module.db.project_id
}

output "database_secret_id" {
  value = module.secrets.secret_ids["${var.app_name}-database-url"]
}

output "runtime_service_account_email" {
  value = google_service_account.runtime.email
}

output "pubsub_topic_names" {
  value = module.messaging.topic_names
}
