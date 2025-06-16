#Infrastructure
#Resources: ResourceGroup, Key Vault, Key Vault Secrets, Storage Account for WebFrontend, HTML Upload in Blob
#Info: These resources are required as frontdoor and storing secrets for the deployment

resource "azurerm_resource_group" "infrastructure" {
  location = local.location
  name = local.infrastructureRGName
}

# Key Vault & Secrets
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

resource "azurerm_key_vault_secret" "localadmin" {
  name = "VmAdminPassword"
  value = "" #fill this manually later
  key_vault_id = azurerm_key_vault.infra.id
}
resource "azurerm_key_vault_secret" "adjoinadmin" {
  name = "adJoinPassword"
  value = "" #fill this manually later
  key_vault_id = azurerm_key_vault.infra.id
}

# Web Frontend - Storage Account Static Website
resource "azurerm_storage_account" "infra" {
  name = local.webStorageAccount
  location = azurerm_resource_group.infrastructure.location
  resource_group_name = azurerm_resource_group.infrastructure.name
  account_tier = "Standard"
  account_replication_type = "LRS"
  public_network_access_enabled = true
  account_kind = "StorageV2"
  tags = local.tags
  network_rules {
    default_action = "Allow"
  }
  static_website {
    index_document = "index.html"
  }
}
# Blob with HTML upload & LogicApp HTTP URL Input
resource "azurerm_storage_blob" "index_html" {
  name                   = "index.html" 
  storage_account_name   = azurerm_storage_account.infra.name
  storage_container_name = "$web"       
  type                   = "Block"
  content_type           = "text/html"

  source_content = replace(file("${path.module}/../src/index.html"), "IHRE_PROXY_LOGIC_APP_HTTP_ENDPUNKT_HIER_EINSETZEN", azurerm_logic_app_trigger_http_request.this.callback_url)

  depends_on = [
    azurerm_storage_account.infra, 
    azurerm_logic_app_workflow.proxy_logic_app 
  ]
}
