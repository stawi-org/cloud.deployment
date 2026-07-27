# Global HTTPS LB + Cloudflare DNS for identity public hostnames.
# Classic Cloud Run domain mapping is not available in europe-west9.

provider "google" {
  project = var.project_id
  region  = var.region
}

# Token from CI: CLOUDFLARE_API_TOKEN / TF_VAR_cloudflare_api_token
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  zone_name = "stawi.org"
  # Control plane only — Google Cert Manager + grey-cloud DNS.
  # accounts / oauth2: Cloudflare DNS CNAME → *.run.app (no Google LB, no Worker).
  # Product APIs: CF Worker on api.stawi.org only.
  hosts = {
    "oauth2-w.stawi.org" = { service = "identity-oauth2-hydra-admin" }
    "authz.stawi.org"    = { service = "identity-authorization-keto-read" }
    "authz-w.stawi.org"  = { service = "identity-authorization-keto-write" }
  }
  host_short = {
    for h in keys(local.hosts) : h => trimsuffix(h, ".${local.zone_name}")
  }
}

# ---------------------------------------------------------------------------
# Adopt pre-existing Cloudflare records (legacy CNAME / wrong A) so OpenTofu
# can replace them with the LB A records. Import blocks must live at root.
# ---------------------------------------------------------------------------

data "cloudflare_dns_records" "zone" {
  zone_id   = var.cloudflare_zone_id
  max_items = 5000
}

locals {
  # CF returns FQDN names; index by short label under stawi.org.
  cf_records_by_short = {
    for r in try(data.cloudflare_dns_records.zone.result, []) :
    trimsuffix(trimsuffix(lower(r.name), "."), ".${local.zone_name}") => r...
  }

  # Prefer importing a CNAME/A/AAAA for each traffic host (first match).
  # Resources already in state skip import automatically.
  traffic_to_import = {
    for host, short in local.host_short :
    host => {
      record_id = [
        for r in lookup(local.cf_records_by_short, short, []) : r.id
        if contains(["A", "AAAA", "CNAME"], upper(r.type))
      ][0]
    }
    if length([
      for r in lookup(local.cf_records_by_short, short, []) : r
      if contains(["A", "AAAA", "CNAME"], upper(r.type))
    ]) > 0
  }

  # ACME CNAMEs Google already expects — adopt if present (same content preferred).
  acme_to_import = {
    for host, short in local.host_short :
    host => {
      record_id = [
        for r in lookup(local.cf_records_by_short, "_acme-challenge.${short}", []) : r.id
        if upper(r.type) == "CNAME"
      ][0]
    }
    if length([
      for r in lookup(local.cf_records_by_short, "_acme-challenge.${short}", []) : r
      if upper(r.type) == "CNAME"
    ]) > 0
  }
}

import {
  for_each = local.traffic_to_import
  to       = module.lb.cloudflare_dns_record.traffic_a[each.key]
  id       = "${var.cloudflare_zone_id}/${each.value.record_id}"
}

import {
  for_each = local.acme_to_import
  to       = module.lb.cloudflare_dns_record.acme[each.key]
  id       = "${var.cloudflare_zone_id}/${each.value.record_id}"
}

module "lb" {
  source     = "../../../modules/cloudrun-host-lb"
  project_id = var.project_id
  name       = "edge-id"
  region     = var.region
  labels     = var.labels

  hosts = local.hosts

  cloudflare_zone_id = var.cloudflare_zone_id
  # Always grey-cloud for control plane — Cloudflare must not MITM Keto/Hydra admin.
  cloudflare_proxied = false
}
