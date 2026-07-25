output "service_uri" {
  value = module.service.uri
}

output "public_hostname" {
  value = var.public_hostname
}

output "domain_mapping_enabled" {
  value = var.enable_domain_mapping
}

output "dns_records" {
  value = module.domain.dns_records
}

output "caddy_routes" {
  value = local.route_backends
}
