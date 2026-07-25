# Cloud Run custom domain mapping (host → single service, path / only).
#
# DEPRECATED for this fleet: europe-west9 returns 501 for domain mappings.
# Public edge is OpenTofu-managed via modules/cloudrun-host-lb + edge-lb-* apps
# (Global HTTPS LB + Certificate Manager + Cloudflare DNS). Keep `enabled=false`.
#
# Does NOT support path-based multi-service routing.

resource "google_cloud_run_domain_mapping" "this" {
  count = var.enabled ? 1 : 0

  # Domain mappings use the v1 API; location must match the service region.
  location = var.region
  name     = var.domain
  project  = var.project_id

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name       = var.service_name
    certificate_mode = var.certificate_mode
    # force_override not exposed consistently; use gcloud --force-override if needed
  }
}
