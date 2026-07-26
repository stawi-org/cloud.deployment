output "service_uri" {
  value = module.frame.service_uri
}

output "public_url" {
  description = "Canonical DNS base (https://tenancy.stawi.org) when public_hostname is set"
  value       = local.tenancy_public_url != "" ? local.tenancy_public_url : module.frame.service_uri
}

output "sync_invoke_url" {
  description = "URL used by the hourly sync scheduler / manual sync job"
  value       = local.sync_invoke_url
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
