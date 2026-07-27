output "ip_address" {
  value = try(module.lb[0].ip_address, null)
}

output "dns_authorization_records" {
  value = try(module.lb[0].dns_authorization_records, {})
}

output "host_backends" {
  value = try(module.lb[0].host_backends, {})
}

output "cloudflare_dns_managed" {
  value = try(module.lb[0].cloudflare_dns_managed, false)
}

output "cloudflare_traffic_records" {
  value = try(module.lb[0].cloudflare_traffic_records, {})
}

output "retired" {
  description = "Identity hosts moved to CF orange CNAME / Worker fallback (no Google LB)"
  value       = true
}
