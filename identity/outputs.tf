output "client_id" {
  description = "auth_audience in stacks/core/env/*.tfvars and VITE_ENTRA_CLIENT_ID in Malus-FE."
  value       = azuread_application.malus.client_id
}

output "tenant_id" {
  description = "auth_tenant_id in stacks/core/env/*.tfvars and VITE_ENTRA_TENANT_ID in Malus-FE."
  value       = var.tenant_id
}

output "api_scope" {
  description = "VITE_ENTRA_API_SCOPE in Malus-FE."
  value       = "${azuread_application_identifier_uri.malus.identifier_uri}/access_as_user"
}

output "redirect_uris" {
  value = azuread_application.malus.single_page_application[0].redirect_uris
}
