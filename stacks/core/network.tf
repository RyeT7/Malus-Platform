resource "azurerm_virtual_network" "core" {
  count = local.own_platform

  name                = "vnet-${local.name}"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  address_space       = [var.address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "apps" {
  count = local.own_platform

  name                 = "snet-apps"
  resource_group_name  = azurerm_resource_group.core.name
  virtual_network_name = azurerm_virtual_network.core[0].name
  address_prefixes     = [cidrsubnet(var.address_space, 7, 0)]

  service_endpoint {
    service = "Microsoft.AzureCosmosDB"
  }

  delegation {
    name = "container-apps"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  count = local.own_platform

  name                              = "snet-private-endpoints"
  resource_group_name               = azurerm_resource_group.core.name
  virtual_network_name              = azurerm_virtual_network.core[0].name
  address_prefixes                  = [cidrsubnet(var.address_space, 11, 32)]
  private_endpoint_network_policies = "Enabled"
}

resource "azurerm_subnet" "aks" {
  count = local.own_platform

  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.core.name
  virtual_network_name = azurerm_virtual_network.core[0].name
  address_prefixes     = [cidrsubnet(var.address_space, 6, 2)]

  service_endpoint {
    service = "Microsoft.AzureCosmosDB"
  }
}

resource "azurerm_network_security_group" "apps" {
  count = local.own_platform

  name                = "nsg-${local.name}-apps"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  tags                = local.tags
}

resource "azurerm_network_security_group" "private_endpoints" {
  count = local.own_platform

  name                = "nsg-${local.name}-pe"
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  tags                = local.tags

  security_rule {
    name                       = "allow-sql-from-workloads"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefixes    = [azurerm_subnet.apps[0].address_prefixes[0], azurerm_subnet.aks[0].address_prefixes[0]]
    destination_address_prefix = azurerm_subnet.private_endpoints[0].address_prefixes[0]
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "apps" {
  count = local.own_platform

  subnet_id                 = azurerm_subnet.apps[0].id
  network_security_group_id = azurerm_network_security_group.apps[0].id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  count = local.own_platform

  subnet_id                 = azurerm_subnet.private_endpoints[0].id
  network_security_group_id = azurerm_network_security_group.private_endpoints[0].id
}

resource "azurerm_private_dns_zone" "sql" {
  count = local.own_platform

  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.core.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  count = local.own_platform

  name                = "sql-${local.name}"
  private_dns_zone_id = azurerm_private_dns_zone.sql[0].id
  virtual_network_id  = azurerm_virtual_network.core[0].id
  tags                = local.tags
}
