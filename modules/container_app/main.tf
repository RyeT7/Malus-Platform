terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }
}

resource "azurerm_container_app" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.environment_id
  revision_mode                = "Multiple"
  workload_profile_name        = "Consumption"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  dynamic "ingress" {
    for_each = var.ingress == null ? [] : [var.ingress]

    content {
      external_enabled = ingress.value.external
      target_port      = var.port
      transport        = "http"

      traffic_weight {
        latest_revision = true
        percentage      = 100
      }
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "app"
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      env {
        name  = "PORT"
        value = tostring(var.port)
      }

      env {
        name  = "AZURE_CLIENT_ID"
        value = var.identity_client_id
      }

      dynamic "env" {
        for_each = var.env

        content {
          name  = env.key
          value = env.value
        }
      }

      liveness_probe {
        transport = "HTTP"
        port      = var.port
        path      = "/healthz"
      }

      readiness_probe {
        transport = "HTTP"
        port      = var.port
        path      = "/readyz"
      }

      startup_probe {
        transport = "HTTP"
        port      = var.port
        path      = "/healthz"
      }
    }

    dynamic "http_scale_rule" {
      for_each = var.ingress == null ? [] : [1]

      content {
        name                = "http"
        concurrent_requests = tostring(var.concurrent_requests)
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
      ingress[0].traffic_weight,
    ]
  }
}
