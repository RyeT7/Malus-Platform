output "resource_group" {
  value = azurerm_resource_group.core.name
}

output "gateway_url" {
  description = "Build the frontend with VITE_BACKEND_URL set to this."
  value       = "https://${module.app["gateway"].fqdn}"
}

output "container_apps" {
  value = { for svc, app in module.app : svc => app.name }
}

output "migration_job" {
  description = "Run with `az containerapp job start -g <rg> -n <job>` after rolling a new content image."
  value       = azurerm_container_app_job.migrate.name
}

output "static_web_app" {
  value = azurerm_static_web_app.frontend.name
}

output "frontend_url" {
  value = "https://${azurerm_static_web_app.frontend.default_host_name}"
}

output "service_identities" {
  value = { for svc, id in azurerm_user_assigned_identity.service : svc => id.client_id }
}

output "aks_helm_values" {
  description = "Values for deploy/charts/malus on the AKS showcase: terraform output -raw aks_helm_values > aks.values.yaml"
  sensitive   = true
  value = yamlencode({
    global = {
      appEnv   = var.env
      logLevel = var.log_level
      image = {
        repository = var.image_repository
        tag        = var.image_tag
      }
      workloadIdentity = true
      env              = local.common_env
    }
    services = {
      for svc in local.services : svc => merge(
        {
          identityClientId = azurerm_user_assigned_identity.service[svc].client_id
          env = merge(
            local.service_env[svc],
            svc == "gateway" ? {
              CONTENT_URL         = "http://content"
              INTERACTION_URL     = "http://interaction"
              REALTIME_URL        = "http://realtime"
              TRUST_PROXY_HEADERS = "false"
            } : {},
          )
        },
        svc == "worker" ? {
          keda = {
            namespace = azurerm_servicebus_namespace.core.name
          }
        } : {},
      )
    }
  })
}

output "aks_cluster" {
  value = var.showcase_enabled ? module.aks_showcase[0].name : null
}
