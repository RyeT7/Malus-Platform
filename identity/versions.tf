terraform {
  required_version = ">= 1.12"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.10"
    }
  }

  backend "azurerm" {
    use_azuread_auth = true
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}
