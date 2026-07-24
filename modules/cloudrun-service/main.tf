resource "google_service_account" "runtime" {
  count = var.service_account_email == null ? 1 : 0

  project      = var.project_id
  account_id   = substr(replace(var.name, "_", "-"), 0, 28)
  display_name = "Cloud Run runtime for ${var.name}"
}

locals {
  service_account_email = coalesce(
    var.service_account_email,
    try(google_service_account.runtime[0].email, null),
  )
}

resource "google_cloud_run_v2_service" "this" {
  name     = var.name
  project  = var.project_id
  location = var.region
  ingress  = var.ingress
  labels   = var.labels

  template {
    service_account = local.service_account_email
    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }
    max_instance_request_concurrency = var.concurrency
    containers {
      image = var.image
      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }
      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = var.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }
    }
  }
}

# Public invoker for edge apps (allUsers)
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
