# Identity control-plane hostnames (oauth2*/authz*/accounts) use Cloudflare
# orange CNAME → Cloud Run + Origin Host rewrite (edge/cloudflare-api-gateway).
# No Google Global LB — hosts = {} tears down any leftover edge-id LB (~$18/mo).
#
# Re-add hosts here only if CF Origin Host rewrite is unavailable for gRPC
# (authz*) and you must fall back to a grey Google LB.

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
  # Retired: oauth2*/authz*/accounts → CF direct CNAME (docs/STABLE_DNS.md).
  hosts      = {}
  manage_lb  = length(local.hosts) > 0
  host_short = {
    for h in keys(local.hosts) : h => trimsuffix(h, ".${local.zone_name}")
  }
}

# ---------------------------------------------------------------------------
# Adopt pre-existing Cloudflare records only when managing an LB again.
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

  traffic_to_import = local.manage_lb ? {
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
  } : {}

  acme_to_import = local.manage_lb ? {
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
  } : {}
}

import {
  for_each = local.traffic_to_import
  to       = module.lb[0].cloudflare_dns_record.traffic_a[each.key]
  id       = "${var.cloudflare_zone_id}/${each.value.record_id}"
}

import {
  for_each = local.acme_to_import
  to       = module.lb[0].cloudflare_dns_record.acme[each.key]
  id       = "${var.cloudflare_zone_id}/${each.value.record_id}"
}

# State address migration when introducing count (then count=0 destroys LB).
moved {
  from = module.lb
  to   = module.lb[0]
}

module "lb" {
  count  = local.manage_lb ? 1 : 0
  source = "../../../modules/cloudrun-host-lb"

  project_id = var.project_id
  name       = "edge-id"
  region     = var.region
  labels     = var.labels

  hosts = local.hosts

  cloudflare_zone_id = var.cloudflare_zone_id
  # Grey only if re-enabled for control plane (CF must not MITM if you need
  # end-to-end to Google certs). Preferred path is CF orange + Origin rewrite.
  cloudflare_proxied = false
}
