output "id" {
  value = azurerm_container_app.this.id
}

output "name" {
  value = azurerm_container_app.this.name
}

output "fqdn" {
  value = var.ingress == null ? null : azurerm_container_app.this.ingress[0].fqdn
}

output "internal_url" {
  description = "Address other apps in the same environment use to reach this one."
  value       = "http://${azurerm_container_app.this.name}"
}
