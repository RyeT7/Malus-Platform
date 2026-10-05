variable "location" {
  description = "Region for the state and CI resources. Must be in the subscription's \"Allowed resource deployment regions\" policy."
  type        = string
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the Malus repositories."
  type        = string
}

variable "github_repositories" {
  description = "Repositories that may federate into the CI identity."
  type        = list(string)
  default     = ["Malus-Platform", "Malus-BE", "Malus-FE"]
}

variable "environments" {
  description = "GitHub environments that map to Terraform environments."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "enforce_resource_group_tags" {
  description = "Deny resource groups without env/project tags. Off by default because AKS and Container Apps create their own infrastructure resource groups."
  type        = bool
  default     = false
}

variable "budget_contact_emails" {
  description = "Recipients for monthly budget alerts. Leave empty to skip the budget."
  type        = list(string)
  default     = []
}

variable "monthly_budget" {
  description = "Monthly budget in the subscription currency."
  type        = number
  default     = 10
}
