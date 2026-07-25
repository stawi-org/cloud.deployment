# Shared + app secrets owned by operations-audit.
# Other operations apps only take IAM accessor on hydra-webhook-psk.
#
# hydra-webhook-psk MUST match stawi-identity so private_key_jwt webhooks
# to accounts.stawi.org succeed. CI deploy SA has secretAccessor on the
# identity secret (one-time IAM grant).
#
# audit-signing-key: service expects hex-encoded key material (hex.DecodeString).

data "google_secret_manager_secret_version" "identity_hydra_psk" {
  project = var.identity_project_id
  secret  = "hydra-webhook-psk"
}

resource "random_bytes" "audit_signing" {
  # App expects 64 raw bytes after hex.DecodeString.
  length = 64
}

locals {
  # Keys must stay non-sensitive for app-secrets for_each (see modules/app-secrets).
  generated_secret_ids = toset(["hydra-webhook-psk", "audit-signing-key"])
  generated_secret_values = {
    "hydra-webhook-psk" = data.google_secret_manager_secret_version.identity_hydra_psk.secret_data
    "audit-signing-key" = random_bytes.audit_signing.hex
  }
}
