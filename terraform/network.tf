##############################################################################
# Network for the VM running Prometheus.
# Port 22 and 9090 reachable from your IP only.
##############################################################################

# The address space the VM lives in. Nothing else uses it, but a VM cannot
# exist without a subnet, and a subnet cannot exist without a virtual network.
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-monitoring-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

# A slice of the address space, reserved for Prometheus.
resource "azurerm_subnet" "prometheus" {
  name                 = "snet-prometheus"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

# Firewall. Azure denies inbound traffic by default, so only the two ports
# below are reachable, and only from my own address.
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-prometheus-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  tags                = local.tags

  security_rule {
    name                       = "allow-ssh-from-me"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-prometheus-ui-from-me"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = var.allowed_source_ip
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "prometheus" {
  subnet_id                 = azurerm_subnet.prometheus.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Static, so the address survives a VM restart and stays valid in the NSG
# rules and in my ssh config.
resource "azurerm_public_ip" "pip" {
  name                = "pip-prometheus-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

# The virtual network card: it holds the private address inside the subnet
# and carries the public IP. The VM plugs into this, not into the subnet.
resource "azurerm_network_interface" "nic" {
  name                = "nic-prometheus-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.prometheus.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}
