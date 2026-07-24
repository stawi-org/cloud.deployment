variable "name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "image" {
  type = string
}

variable "container_port" {
  type        = number
  default     = 8080
  description = "Container listen port (Cloud Run sets PORT to this)"
}

variable "command" {
  type        = list(string)
  default     = null
  description = "Optional container entrypoint override"
}

variable "args" {
  type        = list(string)
  default     = null
  description = "Optional container args"
}

variable "service_account_email" {
  type        = string
  default     = null
  description = "If set, use this SA instead of creating one in the module. Prefer root-managed SA so secret IAM can be granted before the service."
}

variable "env" {
  type        = map(string)
  default     = {}
  description = "Plain environment variables"
}

variable "secret_env" {
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default     = {}
  description = "Env vars sourced from Secret Manager"
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "max_instance_count" {
  type        = number
  default     = 5
  description = "Hard cap on instances — keep low for cost; raise per-app under load"
}

variable "min_instance_count" {
  type        = number
  default     = 0
  description = "0 = scale to zero (no idle cost)"
}

variable "concurrency" {
  type    = number
  default = 80
}

variable "cpu_idle" {
  type        = bool
  default     = true
  description = "When true, CPU is allocated only during request processing (cheaper for min_instances=0)"
}

variable "startup_cpu_boost" {
  type        = bool
  default     = true
  description = "Brief CPU boost on cold start — faster wake, minimal extra cost"
}

variable "ingress" {
  type    = string
  default = "INGRESS_TRAFFIC_ALL"
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "deletion_protection" {
  type        = bool
  default     = false
  description = "Cloud Run deletion protection; keep false until greenfield is stable"
}
