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
  env              = "dev"
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
    condition     = azurerm_resource_group.core.tags.env == "dev" && azurerm_resource_group.core.tags.project == "malus"
    error_message = "Resource group must carry env and project tags."
  }

  assert {
    condition     = length(module.aks_showcase) == 0
    error_message = "The AKS showcase is off by default."
  }

  assert {
    condition     = local.service_env.gateway.AUTH_ISSUER == "https://login.microsoftonline.com/00000000-0000-0000-0000-00000000aaaa/v2.0"
    error_message = "Gateway issuer must point at the Entra tenant."
  }
}

run "showcase_toggle" {
  command = plan

  variables {
    showcase_enabled = true
  }

  assert {
    condition     = length(module.aks_showcase) == 1
    error_message = "showcase_enabled must deploy the AKS showcase."
  }
}

run "rejects_unknown_env" {
  command = plan

  variables {
    env = "qa"
  }

  expect_failures = [var.env]
}
