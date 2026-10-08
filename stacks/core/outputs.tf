output "resource_group" {
  value = azurerm_resource_group.core.name
}

output "gateway_url" {
  description = "Build the frontend with VITE_BACKEND_URL set to this."
  value       = "https://${module.app["gateway"].fqdn}"
}

output "container_apps" {
  value = { for svc, app in module.app : svc => app.name }
}

output "migration_job" {
  description = "Run with `az containerapp job start -g <rg> -n <job>` after rolling a new content image."
  value       = azurerm_container_app_job.migrate.name
}

output "static_web_app" {
  value = azurerm_static_web_app.frontend.name
}

output "frontend_url" {
  value = "https://${azurerm_static_web_app.frontend.default_host_name}"
}

output "service_identities" {
  value = { for svc, id in azurerm_user_assigned_identity.service : svc => id.client_id }
}
