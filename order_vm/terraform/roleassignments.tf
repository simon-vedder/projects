
# 8. Role Assignment for Function App (Storage Blob Data Contributor)
resource "azurerm_role_assignment" "function_app_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_id   = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b7e6dc6d-f1e8-4753-8033-0f276bb0955b" # Storage Blob Data Contributor
  principal_id         = azurerm_windows_function_app.create_deployment_function_app.identity[0].principal_id

  depends_on = [
    azurerm_storage_account.main,
    azurerm_windows_function_app.create_deployment_function_app
  ]
}
# 8. Role Assignment for Function App (Contributor)
resource "azurerm_role_assignment" "function_app_vmrg_contributor" {
  scope                = azurerm_resource_group.virtualmachines.id
  role_definition_id   = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c" # Contributor
  principal_id         = azurerm_windows_function_app.create_deployment_function_app.identity[0].principal_id

  depends_on = [
    azurerm_resource_group.virtualmachines,
    azurerm_windows_function_app.create_deployment_function_app
  ]
}
# 8. Role Assignment for Function App (Key Vault Secrets User)
resource "azurerm_role_assignment" "function_app_kv_secretsuser" {
  scope                = azurerm_key_vault.infra.id
  role_definition_id   = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6" # Key Vault Secrets User
  principal_id         = azurerm_windows_function_app.create_deployment_function_app.identity[0].principal_id

  depends_on = [
    azurerm_key_vault.infra,
    azurerm_windows_function_app.create_deployment_function_app
  ]
}

# 9. Role Assignment for Logic App (Storage Queue Data Contributor)
resource "azurerm_role_assignment" "logic_app_storage_queue_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_id   = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/974c5e8b-45b9-4653-ba55-5f855dd0fb88" # Storage Queue Data Contributor
  principal_id         = azurerm_logic_app_workflow.proxy_logic_app.identity[0].principal_id

  depends_on = [
    azurerm_storage_account.main,
    azurerm_logic_app_workflow.proxy_logic_app
  ]
}
# 10. Entra Role for Logic App (Directory Reader)
resource "azuread_directory_role" "logic_app_entra_directory_reader" {
  template_id = "88d8e3e3-8f55-4a1e-953a-9b9898b8876b" # Directory Readers 
}

resource "azuread_directory_role_assignment" "logic_app_entra_directory_reader" {
  role_id   = azuread_directory_role.logic_app_entra_directory_reader.id
  principal_object_id = azurerm_logic_app_workflow.proxy_logic_app.identity[0].principal_id
}
