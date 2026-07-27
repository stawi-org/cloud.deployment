# Keepers pin values for the life of the project. Changing SECRETS_SYSTEM without
# Hydra key re-encryption breaks JWKs (cipher: message authentication failed).
resource "random_password" "secrets_system" {
  length  = 64
  special = false
  keepers = {
    purpose = "hydra-secrets-system-v1"
  }
}

resource "random_password" "secrets_cookie" {
  length  = 64
  special = false
  keepers = {
    purpose = "hydra-secrets-cookie-v1"
  }
}

# Webhook PSK: prefer shared value from authentication apply.
# For standalone apply order, generate if not using data remote state yet.
resource "random_password" "hydra_webhook_psk" {
  length  = 48
  special = false
  keepers = {
    purpose = "hydra-webhook-psk-v1"
  }
}

locals {
  generated_secret_values = {
    "identity-oauth2-hydra-secrets-system" = random_password.secrets_system.result
    "identity-oauth2-hydra-secrets-cookie" = random_password.secrets_cookie.result
    "hydra-webhook-psk"                    = random_password.hydra_webhook_psk.result
  }
}
