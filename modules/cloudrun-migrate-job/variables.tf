variable "name" {
  type        = string
  description = "Cloud Run Job name (e.g. identity-identity-migrate)"
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "image" {
  type        = string
  description = "Same image as the runtime service"
}

variable "service_account_email" {
  type        = string
  description = "Runtime SA (must already have secretAccessor on DB secrets)"
}

variable "command" {
  type        = list(string)
  default     = null
  description = "Optional entrypoint override"
}

variable "args" {
  type        = list(string)
  description = "Migration command args, e.g. [\"migrate\"] or [\"migrate\",\"sql\",\"-e\",\"--yes\"]"
}

variable "env" {
  type        = map(string)
  default     = {}
  description = "Plain env for the migration job"
}

variable "secret_env" {
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default     = {}
  description = "Secret Manager env (prefer direct Neon URL for migrations)"
}

# Mount Secret Manager secrets as files (e.g. Keto keto.yml for migrate).
variable "secret_volumes" {
  type = map(object({
    secret     = string
    mount_path = string
    file_name  = optional(string)
    version    = optional(string, "latest")
  }))
  default     = {}
  description = "Map of volume name → Secret Manager volume mount for the job container"
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "1Gi"
}

variable "timeout" {
  type        = string
  default     = "600s"
  description = "Job task timeout"
}

variable "max_retries" {
  type    = number
  default = 1
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "execute" {
  type        = bool
  default     = true
  description = "If true, execute the job on apply (requires gcloud + credentials on the runner)"
}

variable "execute_trigger" {
  type        = string
  default     = ""
  description = "Extra trigger string to force re-execute (e.g. image digest or schema version)"
}
