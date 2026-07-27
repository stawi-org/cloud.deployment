output "ip_address" {
  description = "Global anycast IP — Cloudflare A for api.stawi.org points here"
  value       = google_compute_global_address.this.address
}

output "ip_name" {
  value = google_compute_global_address.this.name
}

output "hostname" {
  value = local.hostname
}

output "certificate_id" {
  value = google_certificate_manager_certificate.this.id
}

output "dns_authorization_record" {
  description = "CNAME for Certificate Manager DNS validation"
  value = {
    name = google_certificate_manager_dns_authorization.api.dns_resource_record[0].name
    type = google_certificate_manager_dns_authorization.api.dns_resource_record[0].type
    data = google_certificate_manager_dns_authorization.api.dns_resource_record[0].data
  }
}

output "routes" {
  description = "Resolved path → backend mapping"
  value = {
    for k, r in local.routes : k => {
      path_prefix     = r.path_prefix
      service         = r.service
      backend_project = r.backend_project
      region          = r.region
      strip_prefix    = r.strip_prefix
      priority        = r.priority
      backend_service = google_compute_backend_service.run[k].id
    }
  }
}

output "forwarding_rule_https" {
  value = google_compute_global_forwarding_rule.https.name
}

output "cloudflare_dns_managed" {
  value = local.manage_cf
}

output "cloudflare_traffic_record" {
  value = local.manage_cf ? {
    name    = cloudflare_dns_record.traffic_a[0].name
    type    = cloudflare_dns_record.traffic_a[0].type
    content = cloudflare_dns_record.traffic_a[0].content
    proxied = cloudflare_dns_record.traffic_a[0].proxied
  } : null
}
