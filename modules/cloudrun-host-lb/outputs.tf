output "ip_address" {
  description = "Global anycast IP — point Cloudflare A records (DNS-only) here"
  value       = google_compute_global_address.this.address
}

output "ip_name" {
  value = google_compute_global_address.this.name
}

output "certificate_id" {
  value = google_certificate_manager_certificate.this.id
}

output "dns_authorization_records" {
  description = "CNAME records for Certificate Manager DNS validation (add in Cloudflare)"
  value = {
    for host, auth in google_certificate_manager_dns_authorization.host :
    host => {
      name = auth.dns_resource_record[0].name
      type = auth.dns_resource_record[0].type
      data = auth.dns_resource_record[0].data
    }
  }
}

output "host_backends" {
  value = {
    for host, cfg in var.hosts : host => cfg.service
  }
}

output "forwarding_rule_https" {
  value = google_compute_global_forwarding_rule.https.name
}

output "cloudflare_dns_managed" {
  value = local.manage_cf
}

output "cloudflare_traffic_records" {
  value = local.manage_cf ? {
    for h, r in cloudflare_dns_record.traffic_a : h => {
      name    = r.name
      type    = r.type
      content = r.content
      proxied = r.proxied
    }
  } : {}
}
