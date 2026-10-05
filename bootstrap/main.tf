data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

locals {
  suffix = substr(sha1(data.azurerm_subscription.current.subscription_id), 0, 6)
  tags = {
    env     = "shared"
    project = "malus"
  }
}

resource "azurerm_resource_group" "shared" {
  name     = "rg-malus-shared"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                            = "stmalustf${local.suffix}"
  resource_group_name             = azurerm_resource_group.shared.name
  location                        = azurerm_resource_group.shared.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  tags                            = local.tags

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }

    container_delete_retention_policy {
      days = 14
    }
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

resource "azurerm_management_lock" "tfstate" {
  name       = "malus-tfstate-cannotdelete"
  scope      = azurerm_storage_account.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Holds Terraform state for every Malus environment. Remove only to tear down bootstrap."
}

resource "azurerm_role_assignment" "deployer_state" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
