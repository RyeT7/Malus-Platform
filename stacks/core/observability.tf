resource "azurerm_log_analytics_workspace" "core" {
  count = local.own_platform

  name                = "log-${local.name}"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

resource "azurerm_application_insights" "core" {
  name                 = "appi-${local.name}"
  resource_group_name  = azurerm_resource_group.core.name
  location             = azurerm_resource_group.core.location
  workspace_id         = local.log_analytics_workspace_id
  application_type     = "web"
  daily_data_cap_in_gb = var.log_daily_quota_gb
  tags                 = local.tags
}

resource "azapi_update_resource" "otel_agent" {
  count = local.own_platform

  type        = "Microsoft.App/managedEnvironments@2024-10-02-preview"
  resource_id = azurerm_container_app_environment.core[0].id

  body = {
    properties = {
      appInsightsConfiguration = {
        connectionString = azurerm_application_insights.core.connection_string
      }
      openTelemetryConfiguration = {
        tracesConfiguration = {
          destinations = ["appInsights"]
        }
      }
    }
  }
}
