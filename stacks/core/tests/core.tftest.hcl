mock_provider "azapi" {}

mock_provider "azurerm" {
  override_data {
    target = data.azurerm_client_config.current
    values = {
      tenant_id       = "00000000-0000-0000-0000-00000000aaaa"
      subscription_id = "00000000-0000-0000-0000-00000000bbbb"
      object_id       = "00000000-0000-0000-0000-00000000cccc"
      client_id       = "00000000-0000-0000-0000-00000000dddd"
    }
  }
}

variables {
  env              = "prod"
  location         = "eastasia"
  image_repository = "ghcr.io/example/malus-be"
  auth_audience    = "api://malus-api"
}

run "core_defaults" {
  command = plan

  assert {
    condition     = [for svc, s in local.app_settings : svc if try(s.ingress.external, false)] == ["gateway"]
    error_message = "The gateway must be the only app with external ingress."
  }

  assert {
    condition     = azurerm_mssql_server.content.public_network_access_enabled == false
    error_message = "Azure SQL must not be publicly reachable."
  }

  assert {
    condition     = azurerm_mssql_server.content.azuread_administrator[0].azuread_authentication_only
    error_message = "Azure SQL must use Entra-only authentication."
  }

  assert {
    condition     = azurerm_cosmosdb_account.interaction.local_authentication_enabled == false
    error_message = "Cosmos DB keys must be disabled."
  }

  assert {
    condition     = azurerm_storage_account.blobs.shared_access_key_enabled == false
    error_message = "Storage shared keys must be disabled."
  }

  assert {
    condition     = azurerm_resource_group.core.tags.env == "prod" && azurerm_resource_group.core.tags.project == "malus"
    error_message = "Resource group must carry env and project tags."
  }

  assert {
    condition     = local.service_env.gateway.AUTH_ISSUER == "https://login.microsoftonline.com/00000000-0000-0000-0000-00000000aaaa/v2.0"
    error_message = "Gateway issuer must point at the Entra tenant."
  }

  assert {
    condition     = length(azurerm_container_app_environment.core) == 1 && length(azurerm_virtual_network.core) == 1 && length(azurerm_log_analytics_workspace.core) == 1
    error_message = "Without shared_platform_env the stack creates its own Container Apps environment, network and workspace."
  }
}

run "shared_platform" {
  command = plan

  variables {
    shared_platform_env = "prod"
  }

  override_data {
    target = data.azurerm_container_app_environment.shared
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-00000000bbbb/resourceGroups/rg-malus-prod/providers/Microsoft.App/managedEnvironments/cae-malus-prod"
    }
  }

  override_data {
    target = data.azurerm_subnet.shared
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-00000000bbbb/resourceGroups/rg-malus-prod/providers/Microsoft.Network/virtualNetworks/vnet-malus-prod/subnets/snet-apps"
    }
  }

  override_data {
    target = data.azurerm_private_dns_zone.shared_sql
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-00000000bbbb/resourceGroups/rg-malus-prod/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"
    }
  }

  override_data {
    target = data.azurerm_log_analytics_workspace.shared
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-00000000bbbb/resourceGroups/rg-malus-prod/providers/Microsoft.OperationalInsights/workspaces/log-malus-prod"
    }
  }

  assert {
    condition     = length(azurerm_container_app_environment.core) == 0 && length(azurerm_virtual_network.core) == 0 && length(azurerm_subnet.apps) == 0 && length(azurerm_private_dns_zone.sql) == 0 && length(azurerm_log_analytics_workspace.core) == 0
    error_message = "With shared_platform_env the stack must not create its own Container Apps environment, network, DNS zone or workspace."
  }

  assert {
    condition     = local.container_app_environment_id == "/subscriptions/00000000-0000-0000-0000-00000000bbbb/resourceGroups/rg-malus-prod/providers/Microsoft.App/managedEnvironments/cae-malus-prod"
    error_message = "Apps must run in the shared Container Apps environment."
  }
}

run "rejects_unknown_env" {
  command = plan

  variables {
    env = "qa"
  }

  expect_failures = [var.env]
}
