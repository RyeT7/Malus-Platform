data "azurerm_client_config" "current" {}

locals {
  name      = "malus-${var.env}"
  compact   = "malus${var.env}"
  suffix    = substr(sha1("${data.azurerm_client_config.current.subscription_id}/${var.env}"), 0, 6)
  tenant_id = coalesce(var.auth_tenant_id, data.azurerm_client_config.current.tenant_id)

  tags = {
    env     = var.env
    project = "malus"
  }

  services = toset(["gateway", "content", "interaction", "realtime", "worker"])
}

resource "azurerm_resource_group" "core" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "service" {
  for_each = local.services

  name                = "id-${local.name}-${each.key}"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  tags                = local.tags
}
