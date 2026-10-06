data "azuread_client_config" "current" {}

locals {
  api_scope_id  = "dccb9f5a-2d60-4c45-91f6-100458204e7b"
  admin_role_id = "be52285e-e9c4-41aa-972a-854a396ef1a9"
  graph_app_id  = "00000003-0000-0000-c000-000000000000"
}

resource "azuread_application" "malus" {
  display_name     = "Malus"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                         = local.api_scope_id
      value                      = "access_as_user"
      type                       = "User"
      enabled                    = true
      admin_consent_display_name = "Access the Malus API"
      admin_consent_description  = "Lets the Malus frontend call the Malus API as the signed-in user."
      user_consent_display_name  = "Access the Malus API"
      user_consent_description   = "Lets the Malus frontend call the Malus API on your behalf."
    }
  }

  app_role {
    id                   = local.admin_role_id
    value                = var.admin_role
    display_name         = "Admin"
    description          = "Edits presentation content and runs the live session."
    allowed_member_types = ["User"]
    enabled              = true
  }

  single_page_application {
    redirect_uris = [for origin in var.spa_origins : "${trimsuffix(origin, "/")}/redirect.html"]
  }

  required_resource_access {
    resource_app_id = local.graph_app_id

    resource_access {
      id   = data.azuread_service_principal.graph.oauth2_permission_scope_ids["openid"]
      type = "Scope"
    }

    resource_access {
      id   = data.azuread_service_principal.graph.oauth2_permission_scope_ids["profile"]
      type = "Scope"
    }

    resource_access {
      id   = data.azuread_service_principal.graph.oauth2_permission_scope_ids["offline_access"]
      type = "Scope"
    }
  }

  lifecycle {
    ignore_changes = [identifier_uris]
  }
}

resource "azuread_application_identifier_uri" "malus" {
  application_id = azuread_application.malus.id
  identifier_uri = "api://${azuread_application.malus.client_id}"
}

resource "azuread_service_principal" "malus" {
  client_id = azuread_application.malus.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

data "azuread_service_principal" "graph" {
  client_id = local.graph_app_id
}

resource "azuread_service_principal_delegated_permission_grant" "api" {
  service_principal_object_id          = azuread_service_principal.malus.object_id
  resource_service_principal_object_id = azuread_service_principal.malus.object_id
  claim_values                         = ["access_as_user"]
}

resource "azuread_service_principal_delegated_permission_grant" "graph" {
  service_principal_object_id          = azuread_service_principal.malus.object_id
  resource_service_principal_object_id = data.azuread_service_principal.graph.object_id
  claim_values                         = ["openid", "profile", "offline_access"]
}

resource "azuread_invitation" "admin" {
  for_each = toset(var.admin_emails)

  user_email_address = each.value
  redirect_url       = "https://myapps.microsoft.com/?tenantid=${var.tenant_id}"

  message {
    body = "You have been invited as an admin of the Malus presentation."
  }
}

locals {
  admin_object_ids = merge(
    { deployer = data.azuread_client_config.current.object_id },
    { for email, invitation in azuread_invitation.admin : email => invitation.user_id },
  )
}

resource "azuread_app_role_assignment" "admin" {
  for_each = local.admin_object_ids

  app_role_id         = local.admin_role_id
  principal_object_id = each.value
  resource_object_id  = azuread_service_principal.malus.object_id
}
