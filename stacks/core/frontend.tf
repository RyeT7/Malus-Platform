resource "azurerm_static_web_app" "frontend" {
  name                = "stapp-${local.name}"
  resource_group_name = azurerm_resource_group.core.name
  location            = var.static_web_app_location
  sku_tier            = "Free"
  sku_size            = "Free"
  tags                = local.tags
}
