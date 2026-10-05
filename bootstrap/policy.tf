locals {
  required_tags = toset(["env", "project"])
}

data "azurerm_policy_definition" "require_rg_tag" {
  display_name = "Require a tag on resource groups"
}

data "azurerm_policy_definition" "inherit_rg_tag" {
  display_name = "Inherit a tag from the resource group if missing"
}

data "azurerm_policy_definition" "sql_public_access" {
  display_name = "Public network access on Azure SQL Database should be disabled"
}

resource "azurerm_subscription_policy_assignment" "require_rg_tag" {
  for_each = local.required_tags

  name                 = "malus-require-rg-tag-${each.key}"
  display_name         = "Malus: require '${each.key}' tag on resource groups"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition.require_rg_tag.id
  enforce              = var.enforce_resource_group_tags
  parameters           = jsonencode({ tagName = { value = each.key } })

  depends_on = [azurerm_resource_group.shared]
}

resource "azurerm_subscription_policy_assignment" "inherit_rg_tag" {
  for_each = local.required_tags

  name                 = "malus-inherit-rg-tag-${each.key}"
  display_name         = "Malus: inherit '${each.key}' tag from resource group"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition.inherit_rg_tag.id
  location             = var.location
  parameters           = jsonencode({ tagName = { value = each.key } })

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "inherit_rg_tag" {
  for_each = local.required_tags

  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Tag Contributor"
  principal_id         = azurerm_subscription_policy_assignment.inherit_rg_tag[each.key].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_subscription_policy_assignment" "sql_public_access" {
  name                 = "malus-deny-public-sql"
  display_name         = "Malus: deny public network access on Azure SQL"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition.sql_public_access.id
  parameters           = jsonencode({ effect = { value = "Deny" } })
}

resource "azurerm_consumption_budget_subscription" "monthly" {
  count = length(var.budget_contact_emails) > 0 ? 1 : 0

  name            = "malus-monthly"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.monthly_budget
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
  }

  notification {
    operator       = "GreaterThan"
    threshold      = 80
    threshold_type = "Forecasted"
    contact_emails = var.budget_contact_emails
  }

  notification {
    operator       = "GreaterThan"
    threshold      = 100
    contact_emails = var.budget_contact_emails
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
