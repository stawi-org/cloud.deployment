output "service_uri" {
  value = module.frame.service_uri
}

output "service_name" {
  value = module.frame.service_name
}

output "runtime_service_account" {
  value = module.frame.runtime_service_account_email
}

output "events_ref" {
  value = module.frame.events_ref
}

output "pubsub_topic_names" {
  value = module.frame.pubsub_topic_names
}

output "neon_project_id" {
  value = module.frame.neon_project_id
}

output "sync_job_name" {
  value = module.sync_job.name
}
