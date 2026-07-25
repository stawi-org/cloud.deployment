# Host-based HTTPS front door for Cloud Run when classic domain mapping is
# unavailable (e.g. europe-west9).
#
# Per hostname: serverless NEG → backend service → URL map host rule.
# TLS: Certificate Manager (Google-managed) + DNS authorizations (CNAME records).
# Global external Application Load Balancer (EXTERNAL_MANAGED).

locals {
  hostnames = sort(keys(var.hosts))
}

# ---------------------------------------------------------------------------
# Certificate Manager — one DNS auth per hostname, one multi-SAN cert
# ---------------------------------------------------------------------------

resource "google_certificate_manager_dns_authorization" "host" {
  for_each = var.hosts

  project  = var.project_id
  name     = substr(replace("${var.name}-${replace(each.key, ".", "-")}", "--", "-"), 0, 63)
  domain   = each.key
  labels   = var.labels
  location = "global"
}

resource "google_certificate_manager_certificate" "this" {
  project  = var.project_id
  name     = "${var.name}-cert"
  labels   = var.labels
  location = "global"

  managed {
    domains = local.hostnames
    dns_authorizations = [
      for h in local.hostnames : google_certificate_manager_dns_authorization.host[h].id
    ]
  }
}

resource "google_certificate_manager_certificate_map" "this" {
  project  = var.project_id
  name     = "${var.name}-certmap"
  labels   = var.labels
}

resource "google_certificate_manager_certificate_map_entry" "host" {
  for_each = var.hosts

  project      = var.project_id
  name         = substr(replace("${var.name}-cme-${replace(each.key, ".", "-")}", "--", "-"), 0, 63)
  map          = google_certificate_manager_certificate_map.this.name
  certificates = [google_certificate_manager_certificate.this.id]
  hostname     = each.key
  labels       = var.labels
}

# ---------------------------------------------------------------------------
# Serverless NEGs + backends (one per host/service)
# ---------------------------------------------------------------------------

resource "google_compute_region_network_endpoint_group" "run" {
  for_each = var.hosts

  project               = var.project_id
  name                  = substr(replace("${var.name}-neg-${each.value.service}", "_", "-"), 0, 63)
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = each.value.service
  }
}

resource "google_compute_backend_service" "run" {
  for_each = var.hosts

  project               = var.project_id
  name                  = substr(replace("${var.name}-bes-${each.value.service}", "_", "-"), 0, 63)
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  # Cloud Run handles authz/timeouts; no health checks on serverless NEGs.

  backend {
    group = google_compute_region_network_endpoint_group.run[each.key].id
  }
}

# ---------------------------------------------------------------------------
# URL map — host-based routing
# ---------------------------------------------------------------------------

resource "google_compute_url_map" "https" {
  project = var.project_id
  name    = "${var.name}-https"

  # Unused default — every real host has a host_rule
  default_service = google_compute_backend_service.run[local.hostnames[0]].id

  dynamic "host_rule" {
    for_each = var.hosts
    content {
      hosts        = [host_rule.key]
      path_matcher = "pm-${replace(host_rule.key, ".", "-")}"
    }
  }

  dynamic "path_matcher" {
    for_each = var.hosts
    content {
      name            = "pm-${replace(path_matcher.key, ".", "-")}"
      default_service = google_compute_backend_service.run[path_matcher.key].id
    }
  }
}

resource "google_compute_url_map" "http_redirect" {
  count = var.enable_http_redirect ? 1 : 0

  project = var.project_id
  name    = "${var.name}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# ---------------------------------------------------------------------------
# Proxies + forwarding rules
# ---------------------------------------------------------------------------

resource "google_compute_target_https_proxy" "this" {
  project         = var.project_id
  name            = "${var.name}-https-proxy"
  url_map         = google_compute_url_map.https.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.this.id}"

  depends_on = [google_certificate_manager_certificate_map_entry.host]
}

resource "google_compute_global_address" "this" {
  project = var.project_id
  name    = "${var.name}-ip"
}

resource "google_compute_global_forwarding_rule" "https" {
  project               = var.project_id
  name                  = "${var.name}-https-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.this.id
  ip_address            = google_compute_global_address.this.id
}

resource "google_compute_target_http_proxy" "redirect" {
  count = var.enable_http_redirect ? 1 : 0

  project = var.project_id
  name    = "${var.name}-http-proxy"
  url_map = google_compute_url_map.http_redirect[0].id
}

resource "google_compute_global_forwarding_rule" "http" {
  count = var.enable_http_redirect ? 1 : 0

  project               = var.project_id
  name                  = "${var.name}-http-fr"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.redirect[0].id
  ip_address            = google_compute_global_address.this.id
}
