module "aks_showcase" {
  source = "../../modules/aks_showcase"
  count  = var.showcase_enabled ? 1 : 0

  name                       = "aks-${local.name}"
  resource_group_name        = azurerm_resource_group.core.name
  location                   = azurerm_resource_group.core.location
  subnet_id                  = azurerm_subnet.aks.id
  node_vm_size               = var.aks_node_vm_size
  log_analytics_workspace_id = azurerm_log_analytics_workspace.core.id
  tags                       = local.tags

  workload_identities = {
    for svc in local.services : svc => azurerm_user_assigned_identity.service[svc].id
  }
}
