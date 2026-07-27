output "ip_address" {
  value = module.gateway.ip_address
}

output "hostname" {
  value = module.gateway.hostname
}

output "routes" {
  value = module.gateway.routes
}

output "dns_authorization_record" {
  value = module.gateway.dns_authorization_record
}

output "cloudflare_dns_managed" {
  value = module.gateway.cloudflare_dns_managed
}

output "cloudflare_traffic_record" {
  value = module.gateway.cloudflare_traffic_record
}
