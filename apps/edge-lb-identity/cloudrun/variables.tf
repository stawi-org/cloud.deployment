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
# CI may still export these; unused.
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
  type    = string
  default = "unused"
  description = "Unused — LB stack has no container image"
}
