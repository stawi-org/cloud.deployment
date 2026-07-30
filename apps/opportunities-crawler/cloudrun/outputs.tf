output "service_uri" {
  value = module.frame.service_uri
}

output "service_name" {
  value = module.frame.service_name
}

output "runtime_service_account" {
  value = module.frame.runtime_service_account_email
}

output "neon_project_id" {
  value = module.frame.neon_project_id
}

output "database_url_secret" {
  description = "Secret Manager id for pooled crawl DATABASE_URL"
  value       = "opportunities-crawler-database-url"
}

output "database_url_direct_secret" {
  description = "Secret Manager id for direct crawl DATABASE_URL (migrate)"
  value       = "opportunities-crawler-database-url-direct"
}
