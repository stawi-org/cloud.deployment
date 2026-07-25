# Global HTTPS LB + Cloudflare DNS for operations public hostnames.

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  zone_name = "stawi.org"
  hosts = {
    "audit.stawi.org"      = { service = "operations-audit" }
    "formstore.stawi.org"  = { service = "operations-formstore" }
    "queuestore.stawi.org" = { service = "operations-queuestore" }
    "redirect.stawi.org"   = { service = "operations-redirect" }
    "thesa.stawi.org"      = { service = "operations-thesa" }
    "trustage.stawi.org"   = { service = "operations-trustage" }
  }
  host_short = {
    for h in keys(local.hosts) : h => trimsuffix(h, ".${local.zone_name}")
  }
}

data "cloudflare_dns_records" "zone" {
  zone_id   = var.cloudflare_zone_id
  max_items = 5000
}

locals {
  cf_records_by_short = {
    for r in try(data.cloudflare_dns_records.zone.result, []) :
    trimsuffix(trimsuffix(lower(r.name), "."), ".${local.zone_name}") => r...
  }

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
  name       = "edge-ops"
  region     = var.region
  labels     = var.labels

  hosts = local.hosts

  cloudflare_zone_id = var.cloudflare_zone_id
  cloudflare_proxied = var.cloudflare_proxied
}
