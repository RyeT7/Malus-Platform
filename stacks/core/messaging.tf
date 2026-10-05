resource "azurerm_servicebus_namespace" "core" {
  name                = "sb-${local.name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  sku                 = "Basic"
  local_auth_enabled  = false
  minimum_tls_version = "1.2"
  tags                = local.tags
}

resource "azurerm_servicebus_queue" "jobs" {
  for_each = toset(["moderation", "pdf-export", "notifications"])

  name                                 = each.key
  namespace_id                         = azurerm_servicebus_namespace.core.id
  max_delivery_count                   = 5
  dead_lettering_on_message_expiration = true
  default_message_ttl                  = "P7D"
}

resource "azurerm_role_assignment" "servicebus_sender" {
  for_each = toset(["content", "interaction"])

  scope                = azurerm_servicebus_namespace.core.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_user_assigned_identity.service[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "servicebus_receiver" {
  scope                = azurerm_servicebus_namespace.core.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_user_assigned_identity.service["worker"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_web_pubsub" "realtime" {
  name                          = "wps-${local.name}-${local.suffix}"
  resource_group_name           = azurerm_resource_group.core.name
  location                      = azurerm_resource_group.core.location
  sku                           = var.webpubsub_sku
  capacity                      = 1
  local_auth_enabled            = false
  public_network_access_enabled = true
  tags                          = local.tags
}

resource "azurerm_role_assignment" "webpubsub_owner" {
  scope                = azurerm_web_pubsub.realtime.id
  role_definition_name = "Web PubSub Service Owner"
  principal_id         = azurerm_user_assigned_identity.service["realtime"].principal_id
  principal_type       = "ServicePrincipal"
}
