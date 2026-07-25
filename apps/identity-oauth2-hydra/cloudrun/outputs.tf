output "service_uri" {
  description = "Hydra public OIDC base URL"
  value       = module.service.uri
}

output "admin_uri" {
  description = "Hydra admin base URL (IAM-protected; not on edge LB)"
  value       = module.service_admin.uri
}

output "admin_service_name" {
  value = module.service_admin.name
}

output "project_id" {
  value = var.project_id
}

output "neon_project_id" {
  value = module.db.project_id
}

output "database_secret_id" {
  value = module.secrets.secret_ids["${var.app_name}-database-url"]
  # same as local.database_secret_id in main.tf
}

output "runtime_service_account_email" {
  value = google_service_account.runtime.email
}

output "pubsub_topic_names" {
  value = module.messaging.topic_names
}

output "admin_exposure" {
  value = var.admin_exposure
}
