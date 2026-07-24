# GCP Secret Manager for application secrets (DB URLs, OAuth secrets, etc.).
#
# for_each keys MUST stay non-sensitive. Never derive for_each from maps marked
# sensitive (e.g. secret_values or random_password results) — that panics OpenTofu
# with "value is marked, so must be unmarked first".

resource "google_secret_manager_secret" "this" {
  for_each = var.secret_ids

  project   = var.project_id
  secret_id = each.key
  labels    = var.labels

  dynamic "replication" {
    for_each = length(var.replication_user_managed_locations) == 0 ? [1] : []
    content {
      auto {}
    }
  }

  dynamic "replication" {
    for_each = length(var.replication_user_managed_locations) > 0 ? [1] : []
    content {
      user_managed {
        dynamic "replicas" {
          for_each = var.replication_user_managed_locations
          content {
            location = replicas.value
          }
        }
      }
    }
  }
}

resource "google_secret_manager_secret_version" "managed" {
  # Explicit non-sensitive set of IDs that have tofu-managed values.
  for_each = var.version_ids

  secret      = google_secret_manager_secret.this[each.key].id
  secret_data = var.secret_values[each.key]
}

resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = {
    for pair in setproduct(var.secret_ids, var.accessor_members) :
    "${pair[0]}|${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
