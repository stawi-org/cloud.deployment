# Unified path-based API gateway for api.stawi.org.
# Frontend lives in the api GCP project; backends are created in each domain project.

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  zone_name  = "stawi.org"
  host_short = trimsuffix(var.hostname, ".${local.zone_name}")

  # Canonical product API surface — keep in sync with config/public-edge.yaml.
  # Host exceptions (accounts, oauth2, authz) stay on edge-lb-*.
  routes = {
    # Identity product APIs
    profile = {
      path_prefix     = "/profile"
      service         = "identity-profile"
      backend_project = var.identity_project_id
      region          = var.region
    }
    tenancy = {
      path_prefix     = "/tenancy"
      service         = "identity-tenancy"
      backend_project = var.identity_project_id
      region          = var.region
    }
    identity = {
      path_prefix     = "/identity"
      service         = "identity-identity"
      backend_project = var.identity_project_id
      region          = var.region
    }

    # Platform product APIs
    devices = {
      path_prefix     = "/devices"
      service         = "platform-devices"
      backend_project = var.platform_project_id
      region          = var.region
    }
    settings = {
      path_prefix     = "/settings"
      service         = "platform-settings"
      backend_project = var.platform_project_id
      region          = var.region
    }
    geolocation = {
      path_prefix     = "/geolocation"
      service         = "platform-geolocation"
      backend_project = var.platform_project_id
      region          = var.region
    }
    files = {
      path_prefix     = "/files"
      service         = "platform-files"
      backend_project = var.platform_project_id
      region          = var.region
    }

    # Operations product APIs
    audit = {
      path_prefix     = "/audit"
      service         = "operations-audit"
      backend_project = var.operations_project_id
      region          = var.region
    }
    formstore = {
      path_prefix     = "/formstore"
      service         = "operations-formstore"
      backend_project = var.operations_project_id
      region          = var.region
    }
    queuestore = {
      path_prefix     = "/queuestore"
      service         = "operations-queuestore"
      backend_project = var.operations_project_id
      region          = var.region
    }
    redirect = {
      path_prefix     = "/redirect"
      service         = "operations-redirect"
      backend_project = var.operations_project_id
      region          = var.region
    }
    thesa = {
      path_prefix     = "/thesa"
      service         = "operations-thesa"
      backend_project = var.operations_project_id
      region          = var.region
    }
    trustage = {
      path_prefix     = "/trustage"
      service         = "operations-trustage"
      backend_project = var.operations_project_id
      region          = var.region
    }
  }
}

# ---------------------------------------------------------------------------
# Adopt pre-existing Cloudflare records for api.stawi.org
# ---------------------------------------------------------------------------

data "cloudflare_dns_records" "zone" {
  zone_id   = var.cloudflare_zone_id
  max_items = 5000
}

locals {
  cf_records_by_short = {
    for r in try(data.cloudflare_dns_records.zone.result, []) :
    trimsuffix(trimsuffix(lower(r.name), "."), ".${local.zone_name}") => r...
  }

  traffic_to_import = length([
    for r in lookup(local.cf_records_by_short, local.host_short, []) : r
    if contains(["A", "AAAA", "CNAME"], upper(r.type))
    ]) > 0 ? {
    api = {
      record_id = [
        for r in lookup(local.cf_records_by_short, local.host_short, []) : r.id
        if contains(["A", "AAAA", "CNAME"], upper(r.type))
      ][0]
    }
  } : {}

  acme_to_import = length([
    for r in lookup(local.cf_records_by_short, "_acme-challenge.${local.host_short}", []) : r
    if upper(r.type) == "CNAME"
    ]) > 0 ? {
    api = {
      record_id = [
        for r in lookup(local.cf_records_by_short, "_acme-challenge.${local.host_short}", []) : r.id
        if upper(r.type) == "CNAME"
      ][0]
    }
  } : {}
}

import {
  for_each = local.traffic_to_import
  to       = module.gateway.cloudflare_dns_record.traffic_a[0]
  id       = "${var.cloudflare_zone_id}/${each.value.record_id}"
}

import {
  for_each = local.acme_to_import
  to       = module.gateway.cloudflare_dns_record.acme[0]
  id       = "${var.cloudflare_zone_id}/${each.value.record_id}"
}

module "gateway" {
  source = "../../../modules/cloudrun-api-gateway"

  project_id     = var.project_id
  name           = "api-gw"
  hostname       = var.hostname
  default_region = var.region
  labels         = var.labels
  routes         = local.routes

  cloudflare_zone_id   = var.cloudflare_zone_id
  cloudflare_proxied   = var.cloudflare_proxied
  cloudflare_zone_name = local.zone_name
}
