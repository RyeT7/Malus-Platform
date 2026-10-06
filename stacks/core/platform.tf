locals {
  shared_platform = var.shared_platform_env != null
  platform_name   = local.shared_platform ? "malus-${var.shared_platform_env}" : local.name
  platform_rg     = "rg-${local.platform_name}"
  own_platform    = local.shared_platform ? 0 : 1
}

data "azurerm_container_app_environment" "shared" {
  count = local.shared_platform ? 1 : 0

  name                = "cae-${local.platform_name}"
  resource_group_name = local.platform_rg
}

data "azurerm_subnet" "shared" {
  for_each = local.shared_platform ? toset(["snet-apps", "snet-private-endpoints", "snet-aks"]) : toset([])

  name                 = each.key
  virtual_network_name = "vnet-${local.platform_name}"
  resource_group_name  = local.platform_rg
}

data "azurerm_private_dns_zone" "shared_sql" {
  count = local.shared_platform ? 1 : 0

  name                = "privatelink.database.windows.net"
  resource_group_name = local.platform_rg
}

data "azurerm_log_analytics_workspace" "shared" {
  count = local.shared_platform ? 1 : 0

  name                = "log-${local.platform_name}"
  resource_group_name = local.platform_rg
}

locals {
  container_app_environment_id = local.shared_platform ? data.azurerm_container_app_environment.shared[0].id : azurerm_container_app_environment.core[0].id
  apps_subnet_id               = local.shared_platform ? data.azurerm_subnet.shared["snet-apps"].id : azurerm_subnet.apps[0].id
  private_endpoints_subnet_id  = local.shared_platform ? data.azurerm_subnet.shared["snet-private-endpoints"].id : azurerm_subnet.private_endpoints[0].id
  aks_subnet_id                = local.shared_platform ? data.azurerm_subnet.shared["snet-aks"].id : azurerm_subnet.aks[0].id
  sql_private_dns_zone_id      = local.shared_platform ? data.azurerm_private_dns_zone.shared_sql[0].id : azurerm_private_dns_zone.sql[0].id
  log_analytics_workspace_id   = local.shared_platform ? data.azurerm_log_analytics_workspace.shared[0].id : azurerm_log_analytics_workspace.core[0].id
}

moved {
  from = azurerm_virtual_network.core
  to   = azurerm_virtual_network.core[0]
}

moved {
  from = azurerm_subnet.apps
  to   = azurerm_subnet.apps[0]
}

moved {
  from = azurerm_subnet.private_endpoints
  to   = azurerm_subnet.private_endpoints[0]
}

moved {
  from = azurerm_subnet.aks
  to   = azurerm_subnet.aks[0]
}

moved {
  from = azurerm_network_security_group.apps
  to   = azurerm_network_security_group.apps[0]
}

moved {
  from = azurerm_network_security_group.private_endpoints
  to   = azurerm_network_security_group.private_endpoints[0]
}

moved {
  from = azurerm_subnet_network_security_group_association.apps
  to   = azurerm_subnet_network_security_group_association.apps[0]
}

moved {
  from = azurerm_subnet_network_security_group_association.private_endpoints
  to   = azurerm_subnet_network_security_group_association.private_endpoints[0]
}

moved {
  from = azurerm_private_dns_zone.sql
  to   = azurerm_private_dns_zone.sql[0]
}

moved {
  from = azurerm_private_dns_zone_virtual_network_link.sql
  to   = azurerm_private_dns_zone_virtual_network_link.sql[0]
}

moved {
  from = azurerm_log_analytics_workspace.core
  to   = azurerm_log_analytics_workspace.core[0]
}

moved {
  from = azurerm_container_app_environment.core
  to   = azurerm_container_app_environment.core[0]
}
