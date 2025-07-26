/*
PowerMate - AzureVM Deallocation Tool (GUI)
Source: ./scripts/PowerMate.*

Usage:
Delete this file if you do not want to deploy it in your environment


Description:
This PowerMate - AzureVM Deallocation Tool is written in PowerShell and got compiled by PS2EXE.
You can find it in the scripts folder - called PowerMate.

It is a simple GUI as an addition for the tag-based PowerManagment solution.
You can give your end-users the possibilty to deallocate instantly instead of shutting vms down without saving potential. 
And also the possibility to skip the scheduled shutdown for that day - if your user want to run a script, rendering some material or mining bitcoins over night ;P

You can find more information within the PowerShell script itself.



!Important
These resources here are for creating the custom role and the user assigned managed identity which has to be assigned to the VMs.
Feel free to use an built in role instead but I would recommend my solution based on the least priviledge principle.

*/


# Custom Role for GUI Tool (VM Management + Tags)
resource "azurerm_role_definition" "vm_gui_manager" {
  name  = "VM GUI Manager"
  scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"

  description = "Custom role for GUI tool to manage VMs and tags"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/write",
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/tags/read",
      "Microsoft.Resources/tags/write"
    ]
    not_actions = []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}

# User Assigned Managed Identity for GUI Tool - assign to each of your VM which will use the GUI
resource "azurerm_user_assigned_identity" "gui_tool" {
  name                = "uami-vm-gui-tool"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

}

# Role Assignment for User Assigned Managed Identity
resource "azurerm_role_assignment" "gui_tool_vm_manager" {
  scope              = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_id = azurerm_role_definition.vm_gui_manager.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.gui_tool.principal_id
}