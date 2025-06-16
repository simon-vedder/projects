resource "azurerm_resource_group" "infrastructure" {
  location = local.location
  name = local.infrastructureRGName
}

#Infrastructure
resource "azurerm_key_vault" "infra" {
  location = azurerm_resource_group.infrastructure.location
  resource_group_name = azurerm_resource_group.infrastructure.name
  name = local.keyVaultName
  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name = "standard"
  enable_rbac_authorization = true
  enabled_for_template_deployment = true
  tags = local.tags
}

resource "azurerm_storage_account" "infra" {
  name = local.webStorageAccount
  location = azurerm_resource_group.infrastructure.location
  resource_group_name = azurerm_resource_group.infrastructure.name
  account_tier = "Standard"
  account_replication_type = "LRS"
  public_network_access_enabled = true
  account_kind = "StorageV2"
  tags = local.tags
  static_website {
    index_document = "index.html"
  }
}
resource "azurerm_storage_blob" "index_html" {
  name                   = "index.html" # Name of the blob in the static website container
  storage_account_name   = azurerm_storage_account.infra.name
  storage_container_name = "$web"       # Special container for static websites
  type                   = "Block"
  content_type           = "text/html"

  # Read the content of the local HTML file and replace the placeholder
  source_content = replace(file("${path.module}/../src/index.html"), "IHRE_PROXY_LOGIC_APP_HTTP_ENDPUNKT_HIER_EINSETZEN", azurerm_logic_app_workflow.proxy_logic_app.access_endpoint)

  depends_on = [
    azurerm_storage_account.infra, # Ensure storage account is ready
    azurerm_logic_app_workflow.proxy_logic_app # Ensure logic app is deployed and its endpoint is available
  ]
}
