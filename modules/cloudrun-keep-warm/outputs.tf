output "job_name" {
  value = google_cloud_scheduler_job.this.name
}

output "job_id" {
  value = google_cloud_scheduler_job.this.id
}

output "schedule" {
  value = var.schedule
}

output "uri" {
  value = var.uri
}
