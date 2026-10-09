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

resource "azurerm_application_insights_standard_web_test" "gateway" {
  count = var.availability_test_enabled ? 1 : 0

  name                    = "webtest-${local.name}-gateway"
  resource_group_name     = azurerm_resource_group.core.name
  location                = azurerm_application_insights.core.location
  application_insights_id = azurerm_application_insights.core.id
  description             = "Gateway /healthz from three Asian regions."
  frequency               = 900
  timeout                 = 30
  retry_enabled           = true
  geo_locations           = ["apac-hk-hkn-azr", "apac-sg-sin-azr", "apac-jp-kaw-edge"]
  tags                    = local.tags

  request {
    url                              = "https://${module.app["gateway"].fqdn}/healthz"
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 7
  }
}

resource "azapi_update_resource" "otel_agent" {
  count = local.own_platform

  type        = "Microsoft.App/managedEnvironments@2024-10-02-preview"
  resource_id = azurerm_container_app_environment.core[0].id

  body = {
    properties = {
      appLogsConfiguration = {
        destination = "log-analytics"
        logAnalyticsConfiguration = {
          customerId = azurerm_log_analytics_workspace.core[0].workspace_id
        }
      }
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

  sensitive_body = {
    properties = {
      appLogsConfiguration = {
        logAnalyticsConfiguration = {
          sharedKey = azurerm_log_analytics_workspace.core[0].primary_shared_key
        }
      }
    }
  }
}
