terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">=4.51.0"
    }
    random = {
      source = "hashicorp/random"
      version = ">=3.7.2"
    }
  }
}


provider "azurerm" {
  features {
  }
  subscription_id = "<subscriptionID>"
}

# Get current subscription
data "azurerm_client_config" "current" {}




###########################################
###             Locals                 ###
###########################################
locals {
  resource_group_name = "securetfsecrets"
  location = "westeurope"

  kv_name = "${local.resource_group_name}-kv"

  vm_prefix = "demo-vm"
  vm_win_name = "${local.vm_prefix}-win"
  vm_unix_name = "${local.vm_prefix}-unix"
  
  admin_username = "superman"
}




###########################################
###          Resourcegroup              ###
###########################################
# Resource Group
resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = local.location
}





###########################################
###             Network                 ###
###########################################
# Networking
resource "azurerm_virtual_network" "this" {
  name                = "vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

}

# Subnet
resource "azurerm_subnet" "this" {
  name                 = "main"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.1.0/24"]
}






###########################################
###          KV & Secrets & Keys        ###
###########################################

# Key Vault
resource "azurerm_key_vault" "this" {
  tenant_id = data.azurerm_client_config.current.tenant_id
  resource_group_name = azurerm_resource_group.this.name
  location = azurerm_resource_group.this.location
  name = local.kv_name
  sku_name = "standard"
  rbac_authorization_enabled = true
}

resource "azurerm_role_assignment" "kv_admin" {
  scope = azurerm_key_vault.this.id
  principal_id = "<userid>"
  role_definition_name = "Key Vault Administrator"
}

resource "random_password" "password" {
length = 16
special = true
override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "password-win" {
  depends_on = [ random_password.password, azurerm_role_assignment.kv_admin ]
  name = "${local.vm_win_name}-${local.admin_username}-pw"
  key_vault_id = azurerm_key_vault.this.id
  value = random_password.password.result
  expiration_date = timeadd(timestamp(), "168h")
  tags = {
    VMName      = local.vm_win_name
    AdminName   = local.admin_username
    OSType      = "Windows"
    Type        = "Password"
    LastRotated = formatdate("YYYY-MM-DD", timestamp())
  }
  lifecycle {
    ignore_changes = [ value,tags,expiration_date ]
  }
}

resource "azurerm_key_vault_secret" "password-unix" {
  depends_on = [ random_password.password, azurerm_role_assignment.kv_admin  ]
  name = "${local.vm_unix_name}-${local.admin_username}-pw"
  key_vault_id = azurerm_key_vault.this.id
  value = random_password.password.result
  expiration_date = timeadd(timestamp(), "168h")
  tags = {
    VMName      = local.vm_unix_name
    AdminName   = local.admin_username
    OSType      = "Linux"
    Type        = "Password"
    LastRotated = formatdate("YYYY-MM-DD", timestamp())
  }
  lifecycle {
    ignore_changes = [ value,tags,expiration_date ]
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "azurerm_key_vault_secret" "ssh-priv" {
  depends_on = [ tls_private_key.ssh, azurerm_role_assignment.kv_admin  ]
  name = "${local.vm_unix_name}-${local.admin_username}-ssh-priv"
  key_vault_id = azurerm_key_vault.this.id
  value = tls_private_key.ssh.private_key_pem
  expiration_date = timeadd(timestamp(), "168h")
  tags = {
    VMName      = local.vm_unix_name
    AdminName   = local.admin_username
    OSType      = "Linux"
    Type        = "SSHKey"
    LastRotated = formatdate("YYYY-MM-DD", timestamp())
  }
  lifecycle {
    ignore_changes = [ value,tags,expiration_date ]
  }
}

resource "azurerm_key_vault_secret" "ssh-pub" {
  depends_on = [ tls_private_key.ssh, azurerm_role_assignment.kv_admin  ]
  name = "${local.vm_unix_name}-${local.admin_username}-ssh-pub"
  key_vault_id = azurerm_key_vault.this.id
  value = tls_private_key.ssh.public_key_openssh
  expiration_date = timeadd(timestamp(), "168h")
  tags = {
    VMName      = local.vm_unix_name
    AdminName   = local.admin_username
    OSType      = "Linux"
    Type        = "SSHPublicKey"
    LastRotated = formatdate("YYYY-MM-DD", timestamp())
  }
  lifecycle {
    ignore_changes = [ value,tags,expiration_date ]
  }
}

###########################################
###            VMs & NICs               ###
###########################################

### Windows
resource "azurerm_windows_virtual_machine" "win" {
  name                = local.vm_win_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = "Standard_B2ms"
  admin_username      = local.admin_username
  admin_password      = azurerm_key_vault_secret.password-win.value

  network_interface_ids = [
    azurerm_network_interface.win.id,
  ]

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
  lifecycle {
    ignore_changes = [ admin_password ]
  }
}
resource "azurerm_network_interface" "win" {
  name                = "${local.vm_win_name}-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "this"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
  }
}


### Linux
resource "azurerm_linux_virtual_machine" "unix" {
  name                = local.vm_unix_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = "Standard_B2ms"
  admin_username      = local.admin_username
  admin_password      = azurerm_key_vault_secret.password-unix.value
  disable_password_authentication = false

  admin_ssh_key {
    username = local.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  network_interface_ids = [
    azurerm_network_interface.unix.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  lifecycle {
    ignore_changes = [ admin_ssh_key, admin_password ]
  }
}
resource "azurerm_network_interface" "unix" {
  name                = "${local.vm_unix_name}-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "this"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
  }
}
