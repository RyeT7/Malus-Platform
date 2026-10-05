variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "environment_id" {
  type = string
}

variable "image" {
  description = "Initial image. CI rolls new images with `az containerapp update`, so later changes are ignored."
  type        = string
}

variable "identity_id" {
  type = string
}

variable "identity_client_id" {
  description = "Exposed as AZURE_CLIENT_ID so DefaultAzureCredential picks the user-assigned identity."
  type        = string
}

variable "env" {
  description = "Plain environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "ingress" {
  description = "Null for no ingress. external = true exposes the app outside the Container Apps environment."
  type = object({
    external = bool
  })
  default = null
}

variable "port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = number
  default = 0.25
}

variable "memory" {
  type    = string
  default = "0.5Gi"
}

variable "min_replicas" {
  type    = number
  default = 0
}

variable "max_replicas" {
  type    = number
  default = 2
}

variable "concurrent_requests" {
  description = "HTTP scale rule threshold. Ignored when ingress is null."
  type        = number
  default     = 50
}

variable "tags" {
  type = map(string)
}
