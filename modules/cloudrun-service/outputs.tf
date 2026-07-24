output "uri" {
  value = google_cloud_run_v2_service.this.uri
}

output "service_account_email" {
  value = local.service_account_email
}

output "name" {
  value = google_cloud_run_v2_service.this.name
}
