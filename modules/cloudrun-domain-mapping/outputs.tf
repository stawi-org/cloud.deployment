output "domain" {
  value = var.domain
}

output "enabled" {
  value = var.enabled
}

output "resource_status" {
  description = "Raw status from the domain mapping (conditions + resourceRecords for DNS)"
  value       = try(google_cloud_run_domain_mapping.this[0].status, null)
}

output "dns_records" {
  description = "DNS records to create at the DNS provider (typically Cloudflare)"
  value = try([
    for rr in google_cloud_run_domain_mapping.this[0].status[0].resource_records : {
      name   = coalesce(try(rr.name, null), var.domain)
      type   = rr.type
      rrdata = rr.rrdata
    }
  ], [])
}

output "mapped" {
  value = var.enabled && length(google_cloud_run_domain_mapping.this) > 0
}
