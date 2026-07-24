output "service_uri" {
  value = module.service.uri
}

output "neon_project_id" {
  value = module.db.project_id
}

output "database_secret_id" {
  value = google_secret_manager_secret.database_url.secret_id
}
