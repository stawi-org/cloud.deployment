# ENCRYPTION_PHRASE for service-files-redirect (AES material).
# Owned here so redirect can apply independently of other ops apps.

resource "random_password" "service_files_encryption" {
  # 32 chars for AES-256-GCM style keys used by service-files
  length  = 32
  special = false
}

locals {
  generated_secret_ids = toset(["service-files-encryption"])
  generated_secret_values = {
    "service-files-encryption" = random_password.service_files_encryption.result
  }
}
