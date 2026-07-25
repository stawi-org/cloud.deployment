terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      # v5 resource is cloudflare_dns_record (same as deployment.infra 04-dns)
      version = "~> 5.0"
    }
  }
}
