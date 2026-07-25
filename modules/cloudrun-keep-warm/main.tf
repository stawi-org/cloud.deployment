# Cheap Cloud Run keep-warm via Cloud Scheduler.
#
# Prefer this over min_instance_count=1 for low-traffic stacks: you pay only for
# the short request (and occasional cold start), not continuous idle min instances.
#
# Target a path that reaches the container (health/ready, /healthz, or even /).
# Public Cloud Run services (allUsers invoker) need no OIDC token on the job.
# attempt_deadline must be long enough for Cloud Run + Neon dual cold start.

resource "google_project_service" "scheduler" {
  count = var.enable_api ? 1 : 0

  project            = var.project_id
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_cloud_scheduler_job" "this" {
  project          = var.project_id
  region           = var.scheduler_region
  name             = var.name
  description      = "Keep-warm ping for Cloud Run (cheap alternative to min instances)"
  schedule         = var.schedule
  time_zone        = var.time_zone
  attempt_deadline = var.attempt_deadline
  paused           = var.paused

  http_target {
    http_method = var.http_method
    uri         = var.uri
    # Public invoker: no OIDC. For private services, add oidc_token { service_account_email = ... }.
    headers = {
      "User-Agent" = "cloud-deployment/keep-warm"
    }
  }

  retry_config {
    retry_count          = 2
    min_backoff_duration = "10s"
    max_backoff_duration = "60s"
    max_doublings        = 2
  }

  depends_on = [google_project_service.scheduler]
}
