
resource "azurerm_resource_group" "virtualmachines" {
  location = local.location
  name = local.virtualmachinesRGName
}

#virtualmachines
resource "azurerm_virtual_desktop_host_pool" "vm" {
  name = local.hostpoolName
  location = azurerm_resource_group.virtualmachines.location
  resource_group_name = azurerm_resource_group.virtualmachines.name
  type = "Personal"
  load_balancer_type = "Persistent"
  personal_desktop_assignment_type = "Automatic"
}

resource "azurerm_virtual_network" "vm" {
  name = local.vnetName
  location = azurerm_resource_group.virtualmachines.location
  resource_group_name = azurerm_resource_group.virtualmachines.name
  address_space = [ "10.0.0.0/16" ]
}

resource "azurerm_subnet" "vm" {
  name = local.subnetName
  resource_group_name = azurerm_resource_group.virtualmachines.name
  virtual_network_name = azurerm_virtual_network.vm.name
  address_prefixes = [ "10.0.0.0/24" ]
}
