output "state_resource_group" {
  value = azurerm_resource_group.shared.name
}

output "state_storage_account" {
  value = azurerm_storage_account.tfstate.name
}

output "state_container" {
  value = azurerm_storage_container.tfstate.name
}

output "github_client_id" {
  description = "Set as the AZURE_CLIENT_ID secret in each GitHub repository."
  value       = azurerm_user_assigned_identity.github.client_id
}

output "tenant_id" {
  description = "Set as the AZURE_TENANT_ID secret in each GitHub repository."
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Set as the AZURE_SUBSCRIPTION_ID secret in each GitHub repository."
  value       = data.azurerm_subscription.current.subscription_id
}
