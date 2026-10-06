locals {
  federated_subjects = merge(
    {
      for pair in setproduct(keys(var.github_repositories), var.environments) :
      "${lower(pair[0])}-${pair[1]}" => "repo:${var.github_owner}@${var.github_owner_id}/${pair[0]}@${var.github_repositories[pair[0]]}:environment:${pair[1]}"
    },
    {
      "malus-platform-pr" = "repo:${var.github_owner}@${var.github_owner_id}/Malus-Platform@${var.github_repositories["Malus-Platform"]}:pull_request"
    },
  )

  delegable_roles = [
    "Storage Blob Data Contributor",
    "Key Vault Secrets User",
    "Key Vault Administrator",
    "Azure Service Bus Data Sender",
    "Azure Service Bus Data Receiver",
    "Web PubSub Service Owner",
    "Network Contributor",
  ]

  delegable_role_guids = join(", ", [
    for name in local.delegable_roles : basename(data.azurerm_role_definition.delegable[name].id)
  ])
}

resource "azurerm_user_assigned_identity" "github" {
  name                = "id-malus-github"
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.federated_subjects

  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.github.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value
}

resource "azurerm_management_lock" "github_identity" {
  name       = "malus-github-identity-readonly"
  scope      = azurerm_user_assigned_identity.github.id
  lock_level = "ReadOnly"
  notes      = "Stops the CI identity from adding federated credentials to itself. Remove only to change the trust rules from bootstrap, then re-apply."

  depends_on = [azurerm_federated_identity_credential.github]
}

data "azurerm_role_definition" "delegable" {
  for_each = toset(local.delegable_roles)

  name  = each.value
  scope = data.azurerm_subscription.current.id
}

resource "azurerm_role_assignment" "github_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "github_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
      )
      OR
      (
        @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegable_role_guids}}
      )
    )
    AND
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
      )
      OR
      (
        @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.delegable_role_guids}}
      )
    )
  EOT
}

resource "azurerm_role_assignment" "github_state" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}
