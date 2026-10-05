variable "env" {
  description = "Environment name; also passed to the services as APP_ENV."
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.env)
    error_message = "env must be dev, prod or test."
  }
}

variable "location" {
  description = "Primary region. Must be in the subscription's \"Allowed resource deployment regions\" policy."
  type        = string
}

variable "static_web_app_location" {
  description = "Static Web Apps only exists in a few regions (westus2, centralus, eastus2, westeurope, eastasia)."
  type        = string
  default     = "eastasia"
}

variable "address_space" {
  type    = string
  default = "10.40.0.0/16"
}

variable "image_repository" {
  description = "Image prefix matching the Malus-BE publish job; each service is pulled from <image_repository>-<service>:<image_tag>, e.g. ghcr.io/owner/malus-be-gateway:sha-<commit>. Packages must be public on GHCR (no registry secret)."
  type        = string
}

variable "image_tag" {
  description = "Tag used only when an app is first created; CI rolls later images."
  type        = string
  default     = "latest"
}

variable "log_level" {
  type    = string
  default = "info"
}

variable "auth_tenant_id" {
  description = "Entra tenant that issues tokens. Defaults to the deploying tenant."
  type        = string
  default     = null
}

variable "auth_audience" {
  description = "Expected `aud` claim on access tokens (the API's app ID URI or client ID)."
  type        = string
}

variable "auth_admin_role" {
  type    = string
  default = "admin"
}

variable "extra_cors_origins" {
  description = "Origins allowed in addition to the Static Web App's default hostname."
  type        = list(string)
  default     = []
}

variable "log_daily_quota_gb" {
  description = "Log Analytics daily ingestion cap."
  type        = number
  default     = 0.15
}

variable "sql_auto_pause_minutes" {
  type    = number
  default = 60
}

variable "cosmos_free_tier" {
  description = "Only one free-tier Cosmos DB account is allowed per subscription; give it to prod. Other environments use serverless."
  type        = bool
  default     = false
}

variable "webpubsub_sku" {
  description = "Free_F1 caps at 20 connections. Switch to Standard_S1 only for rehearsals and presentation day."
  type        = string
  default     = "Free_F1"

  validation {
    condition     = contains(["Free_F1", "Standard_S1"], var.webpubsub_sku)
    error_message = "webpubsub_sku must be Free_F1 or Standard_S1."
  }
}

variable "gateway_min_replicas" {
  description = "0 saves money at idle; set to 1 during presentation week to avoid cold starts."
  type        = number
  default     = 0
}

variable "realtime_max_replicas" {
  type    = number
  default = 5
}

variable "developer_principal_ids" {
  description = "Entra object IDs that get data-plane access to Cosmos DB and Blob Storage for debugging. Leave empty in prod."
  type        = list(string)
  default     = []
}

variable "developer_ip_ranges" {
  description = "Public IPs or CIDRs allowed through the Cosmos DB firewall."
  type        = list(string)
  default     = []
}

variable "showcase_enabled" {
  description = "Deploy the AKS showcase layer. Set true for demos and presentation week, then back to false to destroy it."
  type        = bool
  default     = false
}

variable "aks_node_vm_size" {
  type    = string
  default = "Standard_B2s_v2"
}
