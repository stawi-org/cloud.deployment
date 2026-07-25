output "ip_address" {
  value = module.lb.ip_address
}

output "dns_authorization_records" {
  value = module.lb.dns_authorization_records
}

output "host_backends" {
  value = module.lb.host_backends
}

output "cloudflare_dns_managed" {
  value = module.lb.cloudflare_dns_managed
}

output "cloudflare_traffic_records" {
  value = module.lb.cloudflare_traffic_records
}
