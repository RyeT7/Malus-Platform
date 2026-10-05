mock_provider "azurerm" {}

variables {
  name                = "ca-test"
  resource_group_name = "rg-test"
  environment_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.App/managedEnvironments/cae-test"
  image               = "ghcr.io/example/malus-be/gateway:sha"
  identity_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test"
  identity_client_id  = "11111111-1111-1111-1111-111111111111"
  tags                = { env = "test", project = "malus" }
}

run "internal_by_default_shape" {
  command = plan

  variables {
    ingress = { external = false }
  }

  assert {
    condition     = azurerm_container_app.this.ingress[0].external_enabled == false
    error_message = "Internal apps must not expose external ingress."
  }

  assert {
    condition     = azurerm_container_app.this.template[0].min_replicas == 0
    error_message = "Apps scale to zero by default."
  }

  assert {
    condition     = contains([for e in azurerm_container_app.this.template[0].container[0].env : e.name], "AZURE_CLIENT_ID")
    error_message = "AZURE_CLIENT_ID must be set so DefaultAzureCredential uses the user-assigned identity."
  }
}

run "no_ingress_means_no_http_scaling" {
  command = plan

  assert {
    condition     = length(azurerm_container_app.this.ingress) == 0
    error_message = "Worker-style apps have no ingress."
  }

  assert {
    condition     = length(azurerm_container_app.this.template[0].http_scale_rule) == 0
    error_message = "HTTP scale rules need ingress."
  }
}
