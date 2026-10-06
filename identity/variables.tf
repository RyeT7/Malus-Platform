variable "tenant_id" {
  description = "The Malus Entra tenant that holds the app registration and issues sign-in tokens."
  type        = string
}

variable "spa_origins" {
  description = "Frontend origins allowed to sign in; each gets <origin>/redirect.html as an SPA redirect URI. Add the prod Static Web App URL after the first prod deploy."
  type        = list(string)
  default     = ["http://localhost:5173"]
}

variable "admin_role" {
  description = "App role value the gateway checks (AUTH_ADMIN_ROLE)."
  type        = string
  default     = "admin"
}

variable "admin_emails" {
  description = "Extra accounts to invite as guests and make admins. Pass via TF_VAR_admin_emails to keep addresses out of the repo."
  type        = list(string)
  default     = []
}
