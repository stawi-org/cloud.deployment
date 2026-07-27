# Path-based API gateway for Cloud Run across multiple GCP projects.
#
# Layout (GCP serverless NEG rules):
#   • Backend service + serverless NEG + Cloud Run  → same project (backend_project)
#   • URL map / proxy / IP / Certificate Manager     → gateway project (project_id)
#   • Global external Application Load Balancer may
#     reference backend services in other projects in the org
#     (cross-project service referencing; Shared VPC not required for global).
#
# Path convention (matches K8s Gateway HTTPRoute):
#   clients call  https://api.stawi.org/{path}/…
#   URL map strips {path} so the service sees /…

locals {
  hostname = var.hostname

  # Longer path prefixes first (stable tie-break on key) so nested routes win.
  # Priorities must be unique within a path_matcher. Separator "::" keeps keys intact.
  route_rank = reverse(sort([
    for k, r in var.routes :
    format("%04d::%s", length(trimsuffix(r.path_prefix, "/")), k)
  ]))
  route_priority = {
    for i, rank in local.route_rank :
    split("::", rank)[1] => (i + 1) * 10
  }

  routes = {
    for k, r in var.routes : k => {
      path_prefix     = trimsuffix(r.path_prefix, "/")
      service         = r.service
      backend_project = r.backend_project
      region          = coalesce(r.region, var.default_region)
      strip_prefix    = r.strip_prefix
      priority        = r.priority > 0 ? r.priority : local.route_priority[k]
    }
  }

  cert_name = substr(
    "${var.name}-cert-${substr(sha1(local.hostname), 0, 8)}",
    0,
    63,
  )

  manage_cf = var.cloudflare_zone_id != ""

  # api.stawi.org → "api"
  host_short = trimsuffix(trimsuffix(local.hostname, "."), ".${var.cloudflare_zone_name}")
}

# ---------------------------------------------------------------------------
# Per-route backends in the Cloud Run's project (NEG + backend service)
# ---------------------------------------------------------------------------

resource "google_compute_region_network_endpoint_group" "run" {
  for_each = local.routes

  project               = each.value.backend_project
  name                  = substr(replace("${var.name}-neg-${each.key}", "_", "-"), 0, 63)
  network_endpoint_type = "SERVERLESS"
  region                = each.value.region

  cloud_run {
    service = each.value.service
  }
}

resource "google_compute_backend_service" "run" {
  for_each = local.routes

  project               = each.value.backend_project
  name                  = substr(replace("${var.name}-bes-${each.key}", "_", "-"), 0, 63)
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  # Serverless NEGs: no health checks; Cloud Run owns readiness.

  backend {
    group = google_compute_region_network_endpoint_group.run[each.key].id
  }
}

# ---------------------------------------------------------------------------
# Certificate Manager — single hostname (api.stawi.org)
# ---------------------------------------------------------------------------

resource "google_certificate_manager_dns_authorization" "api" {
  project  = var.project_id
  name     = substr(replace("${var.name}-${replace(local.hostname, ".", "-")}", "--", "-"), 0, 63)
  domain   = local.hostname
  labels   = var.labels
  location = "global"
}

resource "google_certificate_manager_certificate" "this" {
  project  = var.project_id
  name     = local.cert_name
  labels   = var.labels
  location = "global"

  managed {
    domains            = [local.hostname]
    dns_authorizations = [google_certificate_manager_dns_authorization.api.id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_certificate_manager_certificate_map" "this" {
  project = var.project_id
  name    = "${var.name}-certmap"
  labels  = var.labels
}

resource "google_certificate_manager_certificate_map_entry" "api" {
  project      = var.project_id
  name         = substr(replace("${var.name}-cme-${replace(local.hostname, ".", "-")}", "--", "-"), 0, 63)
  map          = google_certificate_manager_certificate_map.this.name
  certificates = [google_certificate_manager_certificate.this.id]
  hostname     = local.hostname
  labels       = var.labels
}

# ---------------------------------------------------------------------------
# URL map — host api.* + path rules with optional prefix strip
# ---------------------------------------------------------------------------

resource "google_compute_url_map" "https" {
  project = var.project_id
  name    = "${var.name}-https"

  # Unmatched paths: bounce to marketing site (no backend leak).
  default_url_redirect {
    https_redirect         = true
    host_redirect          = var.default_redirect_host
    redirect_response_code = "TEMPORARY_REDIRECT"
    strip_query            = false
  }

  host_rule {
    hosts        = [local.hostname]
    path_matcher = "api"
  }

  path_matcher {
    name = "api"

    default_url_redirect {
      https_redirect         = true
      host_redirect          = var.default_redirect_host
      redirect_response_code = "TEMPORARY_REDIRECT"
      strip_query            = false
    }

    dynamic "route_rules" {
      for_each = local.routes
      content {
        priority = route_rules.value.priority
        service  = google_compute_backend_service.run[route_rules.key].id

        # prefix_match "/profile" also matches "/profile/…" (Connect + REST).
        match_rules {
          prefix_match = route_rules.value.path_prefix
        }

        dynamic "route_action" {
          for_each = route_rules.value.strip_prefix ? [1] : []
          content {
            url_rewrite {
              # /profile/foo → /foo ; /profile → /
              path_prefix_rewrite = "/"
            }
          }
        }
      }
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
# Proxies + forwarding rules (gateway project)
# ---------------------------------------------------------------------------

resource "google_compute_target_https_proxy" "this" {
  project         = var.project_id
  name            = "${var.name}-https-proxy"
  url_map         = google_compute_url_map.https.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.this.id}"

  depends_on = [google_certificate_manager_certificate_map_entry.api]
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

# ---------------------------------------------------------------------------
# Cloudflare DNS — A traffic + ACME validation CNAME
# ---------------------------------------------------------------------------

resource "cloudflare_dns_record" "acme" {
  count = local.manage_cf ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "_acme-challenge.${local.host_short}"
  type    = google_certificate_manager_dns_authorization.api.dns_resource_record[0].type
  content = trimsuffix(google_certificate_manager_dns_authorization.api.dns_resource_record[0].data, ".")
  ttl     = 60
  proxied = false

  comment = "Managed by cloud.deployment ${var.name} (cert validation)"
}

resource "cloudflare_dns_record" "traffic_a" {
  count = local.manage_cf ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = local.host_short
  type    = "A"
  content = google_compute_global_address.this.address
  ttl     = var.cloudflare_proxied ? 1 : var.cloudflare_ttl
  proxied = var.cloudflare_proxied

  comment = "Managed by cloud.deployment ${var.name} → path API gateway"

  depends_on = [cloudflare_dns_record.acme]
}
