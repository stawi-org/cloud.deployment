# Shared + app secrets owned by operations-audit (like identity-oauth2-hydra owns hydra-webhook-psk).
# Other operations apps only take IAM accessor on hydra-webhook-psk.
#
# hydra-webhook-psk should ideally match stawi-identity so private_key_jwt webhooks
# accept the signer call. After first apply, re-seed from identity if needed:
#   gcloud secrets versions access latest --secret=hydra-webhook-psk --project=stawi-identity \
#     | gcloud secrets versions add hydra-webhook-psk --project=stawi-operations --data-file=-
#
# audit-signing-key: service expects hex-encoded key material (hex.DecodeString),
# not PEM — PEM dashes fail with: encoding/hex: invalid byte U+002D '-'.

resource "random_password" "hydra_webhook_psk" {
  length  = 48
  special = false
}

resource "random_bytes" "audit_signing" {
  length = 32
}

locals {
  generated_secret_values = {
    "hydra-webhook-psk" = random_password.hydra_webhook_psk.result
    "audit-signing-key" = random_bytes.audit_signing.hex
  }
  generated_secret_ids = toset(keys(local.generated_secret_values))
}
