output "uri" {
  value = google_cloud_run_v2_service.this.uri
}

output "service_account_email" {
  value = google_service_account.runtime.email
}

output "name" {
  value = google_cloud_run_v2_service.this.name
}
