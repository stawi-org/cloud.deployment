# Cloud Run custom domain mapping (host → single service, path / only).
#
# Prerequisites:
#   1. Domain verified for the GCP project/user:
#        gcloud domains verify stawi.org
#   2. After apply, add DNS records from outputs (Cloudflare DNS-only recommended
#      until certificate status is Active).
#
# Does NOT support path-based multi-service routing — use one hostname per
# service, or route paths in Cloudflare if legacy api.stawi.org/* is needed.

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
