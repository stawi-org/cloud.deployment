variable "env" {
  type        = string
  description = "stawi-dev | stawi-prod"
  validation {
    condition     = contains(["stawi-dev", "stawi-prod"], var.env)
    error_message = "env must be stawi-dev or stawi-prod"
  }
}
