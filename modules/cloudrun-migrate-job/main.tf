# Cloud Run Job that runs database migrations, then (optionally) executes
# once on apply so the schema exists before the service starts.
#
# Migration commands (by workload type):
#   Frame services:  args = ["migrate"]
#   Ory Hydra:       args = ["migrate", "sql", "-e", "--yes"]  (DSN from env)
#   Ory Keto:        args = ["migrate", "up", "-y"]            (DSN from env)
#
# Prefer Neon *direct* connection URLs (not pooler) so session advisory locks work.

resource "google_cloud_run_v2_job" "this" {
  name     = var.name
  project  = var.project_id
  location = var.region
  labels   = var.labels

  template {
    labels = var.labels
    template {
      service_account = var.service_account_email
      timeout         = var.timeout
      max_retries     = var.max_retries

      containers {
        image   = var.image
        command = var.command
        args    = var.args

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

  lifecycle {
    ignore_changes = [
      # executions mutate generation; ignore client noise
      client,
      client_version,
    ]
  }
}

# Run migrations on apply when image/args change. Requires gcloud on PATH and
# Application Default Credentials (WIF in CI, user creds locally).
resource "terraform_data" "execute" {
  count = var.execute ? 1 : 0

  triggers_replace = {
    job_uid  = google_cloud_run_v2_job.this.uid
    image    = var.image
    args     = join("\n", coalesce(var.args, []))
    command  = join("\n", coalesce(var.command, []))
    extra    = var.execute_trigger
    # secret versions may change connection strings without job template change
    secrets  = join(",", [for k, v in var.secret_env : "${k}=${v.secret}:${coalesce(v.version, "latest")}"])
  }

  depends_on = [google_cloud_run_v2_job.this]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      if ! command -v gcloud >/dev/null 2>&1; then
        echo "ERROR: gcloud required to execute Cloud Run Job ${var.name}" >&2
        exit 1
      fi
      echo "Executing migration job ${var.name} in ${var.project_id}/${var.region}..."
      gcloud run jobs execute "${var.name}" \
        --project="${var.project_id}" \
        --region="${var.region}" \
        --wait
      echo "Migration job ${var.name} completed successfully"
    EOT
  }
}
