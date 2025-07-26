# Outputs
output "automation_account_name" {
  description = "Name of the Automation Account"
  value       = azurerm_automation_account.main.name
}

output "automation_account_identity_principal_id" {
  description = "Principal ID of the Automation Account System Managed Identity"
  value       = azurerm_automation_account.main.identity[0].principal_id
}

output "custom_role_vm_power_manager_id" {
  description = "ID of the custom VM Power Manager role"
  value       = azurerm_role_definition.vm_power_manager.role_definition_resource_id
}

