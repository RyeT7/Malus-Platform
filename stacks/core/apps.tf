resource "azurerm_container_app_environment" "core" {
  name                               = "cae-${local.name}"
  resource_group_name                = azurerm_resource_group.core.name
  location                           = azurerm_resource_group.core.location
  logs_destination                   = "log-analytics"
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.core.id
  infrastructure_subnet_id           = azurerm_subnet.apps.id
  infrastructure_resource_group_name = "rg-${local.name}-cae-infra"
  internal_load_balancer_enabled     = false
  tags                               = local.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

locals {
  cors_origins = concat(
    ["https://${azurerm_static_web_app.frontend.default_host_name}"],
    var.extra_cors_origins,
  )

  sql_dsn = "sqlserver://${azurerm_mssql_server.content.fully_qualified_domain_name}?database=${azapi_resource.content_db.name}&encrypt=true&fedauth=ActiveDirectoryDefault"

  common_env = {
    APP_ENV                               = var.env
    LOG_LEVEL                             = var.log_level
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.core.connection_string
    KEY_VAULT_URI                         = azurerm_key_vault.core.vault_uri
  }

  service_env = {
    gateway = {
      CONTENT_URL          = "http://ca-${local.name}-content"
      INTERACTION_URL      = "http://ca-${local.name}-interaction"
      REALTIME_URL         = "http://ca-${local.name}-realtime"
      CORS_ALLOWED_ORIGINS = join(",", local.cors_origins)
      TRUST_PROXY_HEADERS  = "true"
      AUTH_ISSUER          = "https://login.microsoftonline.com/${local.tenant_id}/v2.0"
      AUTH_AUDIENCE        = var.auth_audience
      AUTH_JWKS_URL        = "https://login.microsoftonline.com/${local.tenant_id}/discovery/v2.0/keys"
      AUTH_ADMIN_ROLE      = var.auth_admin_role
    }
    content = {
      SQL_DSN              = local.sql_dsn
      BLOB_ENDPOINT        = azurerm_storage_account.blobs.primary_blob_endpoint
      SERVICEBUS_NAMESPACE = "${azurerm_servicebus_namespace.core.name}.servicebus.windows.net"
    }
    interaction = {
      COSMOS_ENDPOINT            = azurerm_cosmosdb_account.interaction.endpoint
      COSMOS_DATABASE            = azurerm_cosmosdb_sql_database.interaction.name
      COSMOS_QUESTIONS_CONTAINER = azurerm_cosmosdb_sql_container.questions.name
      SERVICEBUS_NAMESPACE       = "${azurerm_servicebus_namespace.core.name}.servicebus.windows.net"
    }
    realtime = {
      WEBPUBSUB_ENDPOINT = "https://${azurerm_web_pubsub.realtime.hostname}"
      WEBPUBSUB_HUB      = "presentation"
    }
    worker = {
      BLOB_ENDPOINT        = azurerm_storage_account.blobs.primary_blob_endpoint
      SERVICEBUS_NAMESPACE = "${azurerm_servicebus_namespace.core.name}.servicebus.windows.net"
    }
  }

  app_settings = {
    gateway     = { ingress = { external = true }, min = var.gateway_min_replicas, max = 3 }
    content     = { ingress = { external = false }, min = 0, max = 2 }
    interaction = { ingress = { external = false }, min = 0, max = 3 }
    realtime    = { ingress = { external = false }, min = 0, max = var.realtime_max_replicas }
    worker      = { ingress = null, min = 0, max = 1 }
  }
}

module "app" {
  source   = "../../modules/container_app"
  for_each = local.app_settings

  name                = "ca-${local.name}-${each.key}"
  resource_group_name = azurerm_resource_group.core.name
  environment_id      = azurerm_container_app_environment.core.id
  image               = "${var.image_repository}-${each.key}:${var.image_tag}"
  identity_id         = azurerm_user_assigned_identity.service[each.key].id
  identity_client_id  = azurerm_user_assigned_identity.service[each.key].client_id
  env                 = merge(local.common_env, { OTEL_SERVICE_NAME = each.key }, local.service_env[each.key])
  ingress             = each.value.ingress
  min_replicas        = each.value.min
  max_replicas        = each.value.max
  tags                = local.tags

  depends_on = [
    azurerm_role_assignment.blob_contributor,
    azurerm_role_assignment.key_vault_reader,
    azurerm_cosmosdb_sql_role_assignment.data_contributor,
    azurerm_private_endpoint.sql,
  ]
}

resource "azurerm_container_app_job" "migrate" {
  name                         = "caj-${local.name}-migrate"
  resource_group_name          = azurerm_resource_group.core.name
  location                     = azurerm_resource_group.core.location
  container_app_environment_id = azurerm_container_app_environment.core.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 600
  replica_retry_limit          = 1
  tags                         = local.tags

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.service["content"].id]
  }

  template {
    container {
      name   = "migrate"
      image  = "${var.image_repository}-content:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"
      args   = ["migrate"]

      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.service["content"].client_id
      }

      env {
        name  = "APP_ENV"
        value = var.env
      }

      env {
        name  = "SQL_DSN"
        value = local.sql_dsn
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_private_endpoint.sql]
}
