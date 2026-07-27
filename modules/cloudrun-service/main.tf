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

  # Exposure → ingress. Explicit var.ingress wins when set.
  resolved_ingress = coalesce(var.ingress, (
    var.exposure == "private"
    ? "INGRESS_TRAFFIC_INTERNAL_ONLY"
    : "INGRESS_TRAFFIC_ALL"
  ))

  # allUsers only for public product surfaces (unless explicitly overridden).
  resolved_public_invoker = coalesce(
    var.public_invoker,
    var.exposure == "public",
  )
}

check "private_or_authenticated_should_list_invokers" {
  assert {
    condition = (
      var.exposure == "public"
      || length(var.invoker_members) > 0
      || var.public_invoker == true
    )
    error_message = "exposure=${var.exposure} requires invoker_members (runtime SAs, scheduler SA, etc.) so the service is not unreachable. Set exposure=public only for intentional internet-open APIs."
  }
}

check "public_invoker_forbidden_when_private" {
  assert {
    condition     = !(var.exposure == "private" && local.resolved_public_invoker)
    error_message = "exposure=private cannot grant allUsers (public_invoker). Use invoker_members only."
  }
}

resource "google_cloud_run_v2_service" "this" {
  name     = var.name
  project  = var.project_id
  location = var.region
  ingress  = local.resolved_ingress
  labels   = var.labels

  # Accept ID tokens minted for stable DNS hosts (edge LB), not only run.app.
  custom_audiences = var.custom_audiences

  deletion_protection = var.deletion_protection

  # client/client_version are mutated by gcloud/API clients.
  # Image is managed by OpenTofu from tfvars (bootstrap + explicit bumps).
  # Decentralized ship can still gcloud-update the image; re-apply will
  # converge to the tfvars tag unless ship also bumps envs/*.tfvars.
  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }

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

    dynamic "volumes" {
      for_each = var.gcs_volumes
      content {
        name = volumes.key
        gcs {
          bucket    = volumes.value.bucket
          read_only = volumes.value.read_only
        }
      }
    }

    containers {
      image   = var.image
      command = var.command
      args    = var.args
      ports {
        # h2c = end-to-end HTTP/2 (gRPC). http1 = default REST. Explicit value
        # required so toggling off h2c actually clears the port protocol.
        name           = var.use_http2 ? "h2c" : "http1"
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

      dynamic "volume_mounts" {
        for_each = var.gcs_volumes
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

      # Keys-only + nonsensitive: maps with sensitive values mark the whole
      # collection and crash OpenTofu 1.10 ("value is marked…"). Keys are public.
      dynamic "env" {
        for_each = length(var.env) == 0 ? toset([]) : toset(nonsensitive([for k, _ in var.env : k]))
        content {
          name  = env.value
          value = var.env[env.value]
        }
      }
      dynamic "env" {
        for_each = length(var.secret_env) == 0 ? toset([]) : toset(nonsensitive([for k, _ in var.secret_env : k]))
        content {
          name = env.value
          value_source {
            secret_key_ref {
              secret  = var.secret_env[env.value].secret
              version = var.secret_env[env.value].version
            }
          }
        }
      }
    }
  }
}

# Anonymous internet invoker — public product surfaces only.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count = local.resolved_public_invoker ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Explicit invokers (runtime SAs, keep-warm scheduler SA, cross-project callers).
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = var.invoker_members

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
