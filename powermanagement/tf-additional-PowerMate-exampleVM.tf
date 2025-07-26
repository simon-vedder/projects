/*
PowerMate - AzureVM Deallocation Tool (GUI)
Source: ./scripts/PowerMate.*

Usage:
Delete this file if you do not want to deploy it in your environment


Description:
This is an example VM and not needed to implement!

You only have to implement the required tags within your environment.

tags = {
    AutoShutdown-Exclude     = ""
    AutoShutdown-SkipUntil   = ""
    AutoShutdown-ExcludeOn   = ""
    AutoShutdown-ExcludeDays = ""
  }


But feel free to use this as an example
*/



# Management VM
resource "azurerm_windows_virtual_machine" "main" {
  name                = "vm-management"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2ms"
  admin_username      = "azureuser"
  admin_password      = "ThisShouldBeStoredSomewhereElse123"

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  ###
  # IMPORTANT - User Managed Identity to get the Permissions which are required. 
  ###
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.gui_tool.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  ###
  # IMPORTANT
  ###
  tags = {
    AutoShutdown-Exclude     = ""
    AutoShutdown-SkipUntil   = ""
    AutoShutdown-ExcludeOn   = ""
    AutoShutdown-ExcludeDays = ""
  }
  ###
  #
  ###
}


# Virtual Network for Management VM
resource "azurerm_virtual_network" "main" {
  name                = "vnet-vm-management"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

}

# Subnet
resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "nsg-vm-management"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

# Public IP
resource "azurerm_public_ip" "main" {
  name                = "pip-vm-management"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"

}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "nic-vm-management"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }

}

# Associate Network Security Group to Network Interface
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}