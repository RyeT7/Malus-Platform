terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.8"
    }
  }
}

variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "node_vm_size" {
  description = "Check the regional vCPU quota with `az vm list-usage --location <region>` before changing."
  type        = string
  default     = "Standard_B2s_v2"
}

variable "namespace" {
  type    = string
  default = "malus"
}

variable "workload_identities" {
  description = "Service name to user-assigned identity ID. Each gets a federated credential for the matching Kubernetes service account."
  type        = map(string)
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "tags" {
  type = map(string)
}

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "id-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "cluster_subnet" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "this" {
  name                      = var.name
  resource_group_name       = var.resource_group_name
  location                  = var.location
  dns_prefix                = var.name
  node_resource_group       = "rg-${var.name}-nodes"
  sku_tier                  = "Free"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  local_account_disabled    = false
  tags                      = var.tags

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    node_count                  = 1
    vnet_subnet_id              = var.subnet_id
    os_disk_type                = "Managed"
    os_disk_size_gb             = 30
    temporary_name_for_rotation = "rotate"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
  }

  node_provisioning_profile {
    mode = "Manual"
  }

  workload_autoscaler_profile {
    keda_enabled = true
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = false
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  depends_on = [azurerm_role_assignment.cluster_subnet]
}

resource "azurerm_federated_identity_credential" "workload" {
  for_each = var.workload_identities

  name                      = "aks-${each.key}"
  user_assigned_identity_id = each.value
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.namespace}:${each.key}"
}

output "name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}
