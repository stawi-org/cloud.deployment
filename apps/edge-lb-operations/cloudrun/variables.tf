variable "app_name" { type = string }
variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "europe-west9"
}
variable "platform" { type = string }
variable "labels" {
  type    = map(string)
  default = {}
}
variable "neon_api_key" {
  type      = string
  sensitive = true
  default   = "unused"
}
variable "neon_org_id" {
  type    = string
  default = ""
}
variable "neon_region_id" {
  type    = string
  default = "aws-eu-central-1"
}
variable "image" {
  type        = string
  default     = "unused"
  description = "Unused — LB stack has no container image"
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token (Zone:DNS:Edit on stawi.org). From TF_VAR_cloudflare_api_token / GH secret CLOUDFLARE_API_TOKEN"
}

variable "cloudflare_zone_id" {
  type        = string
  default     = "706bf604a333d866bb38c03bf643e79a"
  description = "Cloudflare zone id for stawi.org"
}

variable "cloudflare_proxied" {
  type        = bool
  default     = false
  description = "CF orange-cloud on traffic A records (false until certs ACTIVE)"
}
