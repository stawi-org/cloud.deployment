output "read_uri" {
  value = module.service_read.uri
}

output "write_uri" {
  value = module.service_write.uri
}

output "migrate_job" {
  value = module.migrate.name
}
