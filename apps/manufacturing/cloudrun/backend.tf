# Partial S3/R2 backend — state key and endpoints supplied at init
terraform {
  backend "s3" {
    bucket                      = "cloud-tofu-state"
    region                      = "auto"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_lockfile                = true
    encrypt                     = true
  }
}
