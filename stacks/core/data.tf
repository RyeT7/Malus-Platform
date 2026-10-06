resource "azurerm_mssql_server" "content" {
  name                          = "sql-${local.name}-${local.suffix}"
  resource_group_name           = azurerm_resource_group.core.name
  location                      = coalesce(var.sql_location, var.location)
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  tags                          = local.tags

  azuread_administrator {
    login_username              = azurerm_user_assigned_identity.service["content"].name
    object_id                   = azurerm_user_assigned_identity.service["content"].principal_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = true
  }
}

resource "azapi_resource" "content_db" {
  type      = "Microsoft.Sql/servers/databases@2025-01-01"
  name      = "malus_content"
  parent_id = azurerm_mssql_server.content.id
  location  = coalesce(var.sql_location, var.location)
  tags      = local.tags

  body = {
    sku = {
      name     = "GP_S_Gen5"
      tier     = "GeneralPurpose"
      family   = "Gen5"
      capacity = 2
    }
    properties = {
      autoPauseDelay                   = var.sql_auto_pause_minutes
      minCapacity                      = 0.5
      maxSizeBytes                     = 34359738368
      useFreeLimit                     = true
      freeLimitExhaustionBehavior      = "AutoPause"
      requestedBackupStorageRedundancy = "Local"
    }
  }
}

resource "azurerm_private_endpoint" "sql" {
  name                = "pe-${local.name}-sql"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "sql"
    private_connection_resource_id = azurerm_mssql_server.content.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "sql"
    private_dns_zone_ids = [azurerm_private_dns_zone.sql.id]
  }
}

resource "azurerm_cosmosdb_account" "interaction" {
  name                         = "cosmos-${local.name}-${local.suffix}"
  resource_group_name          = azurerm_resource_group.core.name
  location                     = coalesce(var.cosmos_location, var.location)
  offer_type                   = "Standard"
  kind                         = "GlobalDocumentDB"
  free_tier_enabled            = var.cosmos_free_tier
  local_authentication_enabled = false
  minimal_tls_version          = "Tls12"

  public_network_access_enabled     = true
  is_virtual_network_filter_enabled = true
  ip_range_filter                   = toset(var.developer_ip_ranges)
  tags                              = local.tags

  virtual_network_rule {
    id = azurerm_subnet.apps.id
  }

  virtual_network_rule {
    id = azurerm_subnet.aks.id
  }

  consistency_policy {
    consistency_level = "Session"
  }

  backup {
    type               = "Periodic"
    storage_redundancy = "Local"
  }

  geo_location {
    location          = coalesce(var.cosmos_location, var.location)
    failover_priority = 0
  }

  dynamic "capabilities" {
    for_each = var.cosmos_free_tier ? [] : ["EnableServerless"]

    content {
      name = capabilities.value
    }
  }
}

resource "azurerm_cosmosdb_sql_database" "interaction" {
  name                = "malus"
  resource_group_name = azurerm_resource_group.core.name
  account_name        = azurerm_cosmosdb_account.interaction.name
  throughput          = var.cosmos_free_tier ? 1000 : null
}

resource "azurerm_cosmosdb_sql_container" "questions" {
  name                  = "questions"
  resource_group_name   = azurerm_resource_group.core.name
  account_name          = azurerm_cosmosdb_account.interaction.name
  database_name         = azurerm_cosmosdb_sql_database.interaction.name
  partition_key_paths   = ["/pk"]
  partition_key_version = 2
}

locals {
  cosmos_data_contributors = merge(
    { interaction = azurerm_user_assigned_identity.service["interaction"].principal_id },
    { for i, id in var.developer_principal_ids : "developer-${i}" => id },
  )
}

resource "azurerm_cosmosdb_sql_role_assignment" "data_contributor" {
  for_each = local.cosmos_data_contributors

  resource_group_name = azurerm_resource_group.core.name
  account_name        = azurerm_cosmosdb_account.interaction.name
  role_definition_id  = "${azurerm_cosmosdb_account.interaction.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = each.value
  scope               = azurerm_cosmosdb_account.interaction.id
}

resource "azurerm_storage_account" "blobs" {
  name                            = "st${local.compact}${local.suffix}"
  resource_group_name             = azurerm_resource_group.core.name
  location                        = azurerm_resource_group.core.location
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
      days = 7
    }

    cors_rule {
      allowed_origins    = local.cors_origins
      allowed_methods    = ["GET", "HEAD", "PUT"]
      allowed_headers    = ["*"]
      exposed_headers    = ["ETag", "Content-Length"]
      max_age_in_seconds = 3600
    }
  }
}

resource "azurerm_storage_container" "blobs" {
  for_each = toset(["attachments", "exports"])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.blobs.id
  container_access_type = "private"
}

locals {
  blob_contributors = merge(
    {
      content = azurerm_user_assigned_identity.service["content"].principal_id
      worker  = azurerm_user_assigned_identity.service["worker"].principal_id
    },
    { for i, id in var.developer_principal_ids : "developer-${i}" => id },
  )
}

resource "azurerm_role_assignment" "blob_contributor" {
  for_each = local.blob_contributors

  scope                = azurerm_storage_account.blobs.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

resource "azurerm_key_vault" "core" {
  name                       = "kv-${local.name}-${local.suffix}"
  resource_group_name        = azurerm_resource_group.core.name
  location                   = azurerm_resource_group.core.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = var.env == "prod"
  soft_delete_retention_days = 7
  tags                       = local.tags
}

resource "azurerm_role_assignment" "key_vault_admin" {
  scope                = azurerm_key_vault.core.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "key_vault_reader" {
  for_each = local.services

  scope                = azurerm_key_vault.core.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.service[each.key].principal_id
  principal_type       = "ServicePrincipal"
}
