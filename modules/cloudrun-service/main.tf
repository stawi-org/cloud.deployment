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

  deletion_protection = var.deletion_protection

  template {
    service_account = local.service_account_email
    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }
    max_instance_request_concurrency = var.concurrency

    dynamic "volumes" {
      for_each = var.secret_volumes
      content {
        name = volumes.key
        secret {
          secret       = volumes.value.secret
          default_mode = 292 # 0444
          dynamic "items" {
            for_each = volumes.value.file_name != null ? [volumes.value.file_name] : []
            content {
              path    = items.value
              version = volumes.value.version
            }
          }
        }
      }
    }

    containers {
      image   = var.image
      command = var.command
      args    = var.args
      ports {
        container_port = var.container_port
      }
      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = var.cpu_idle
        startup_cpu_boost = var.startup_cpu_boost
      }

      dynamic "volume_mounts" {
        for_each = var.secret_volumes
        content {
          name       = volume_mounts.key
          mount_path = volume_mounts.value.mount_path
        }
      }

      dynamic "startup_probe" {
        for_each = var.startup_probe_path != "" ? [1] : []
        content {
          initial_delay_seconds = 10
          timeout_seconds       = 3
          period_seconds        = 5
          failure_threshold     = 30
          http_get {
            path = var.startup_probe_path
            port = var.container_port
          }
        }
      }

      dynamic "liveness_probe" {
        for_each = var.liveness_probe_path != "" ? [1] : []
        content {
          initial_delay_seconds = 30
          timeout_seconds       = 5
          period_seconds        = 10
          failure_threshold     = 3
          http_get {
            path = var.liveness_probe_path
            port = var.container_port
          }
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

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count = var.public_invoker ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
