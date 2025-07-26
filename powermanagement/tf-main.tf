/*
This solution creates the Automation Account incl. Managed Identity with Permissions (Custom Role) to Start and Stop VMs.
Also adds two schedules - one for starting in the morning and one for stopping at the night.

*/

provider "azurerm" {
  features {
  }
  subscription_id = "your-subscription-id"
}

# Get current subscription
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location


}


# Automation Account
resource "azurerm_automation_account" "main" {
  name                = var.automation_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

}

# PowerShell Runbook
resource "azurerm_automation_runbook" "vm_power_management" {
  name                    = "VM-PowerManagement"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell72"

  content = file("${path.module}/scripts/VM-PowerManagement.ps1")
}

# Schedule for VM Start (7 AM, Monday to Friday)
resource "azurerm_automation_schedule" "vm_start" {
  name                    = "vm-start-schedule"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  frequency               = "Week"
  interval                = 1
  timezone                = "Europe/Zurich" #change to your timezone
  week_days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  description = "Schedule to start VMs at 7 AM on weekdays"
}

# Schedule for VM Stop (9 PM, Monday to Friday)
resource "azurerm_automation_schedule" "vm_stop" {
  name                    = "vm-stop-schedule"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  frequency               = "Week"
  interval                = 1
  timezone                = "Europe/Zurich" #change to your timezone
  week_days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  description = "Schedule to stop VMs at 9 PM on weekdays"
}

# Job Schedule for VM Start
resource "azurerm_automation_job_schedule" "vm_start_job" {
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  schedule_name           = azurerm_automation_schedule.vm_start.name
  runbook_name            = azurerm_automation_runbook.vm_power_management.name

  parameters = {
    action = "Start"
  }
}

# Job Schedule for VM Stop
resource "azurerm_automation_job_schedule" "vm_stop_job" {
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  schedule_name           = azurerm_automation_schedule.vm_stop.name
  runbook_name            = azurerm_automation_runbook.vm_power_management.name

  parameters = {
    action = "Stop"
  }
}


# Custom Role for VM Power Management (Least Privilege)
resource "azurerm_role_definition" "vm_power_manager" {
  name  = "VM Power Manager"
  scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"

  description = "Custom role for VM power management with least privilege"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/write",
      "Microsoft.Network/networkInterfaces/join/action",
      "Microsoft.Compute/disks/write",
      "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/deallocate/action"
    ]
    not_actions = []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}


# Role Assignment for Automation Account System Managed Identity
resource "azurerm_role_assignment" "automation_vm_power" {
  scope              = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_id = azurerm_role_definition.vm_power_manager.role_definition_resource_id
  principal_id       = azurerm_automation_account.main.identity[0].principal_id
}