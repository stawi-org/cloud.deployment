output "read_uri" {
  value = module.service_read.uri
}

output "write_uri" {
  value = module.service_write.uri
}

output "migrate_job" {
  value = module.migrate.name
}

output "exposure" {
  value = var.exposure
}

output "invoker_members" {
  value = local.keto_invoker_members
}

output "runtime_service_account" {
  value = google_service_account.runtime.email
}
