# Create Resource Groups
# Create Resources (logic app via arm, function app maybe via zip)
# role assignments
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "automation" {
    location = local.location
    name = local.automationRGName
}


#automations

# 1. Azure Storage Account
resource "azurerm_storage_account" "main" {
  name                     = local.queueStorageAccountName
  resource_group_name      = azurerm_resource_group.automation.name
  location                 = azurerm_resource_group.automation.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"


  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
    virtual_network_subnet_ids = [] 
    ip_rules                   = [] 
  }

  tags = local.tags
}

# 2. Azure Storage Queue
resource "azurerm_storage_queue" "order_queue" {
  name                = local.queueName
  storage_account_name = azurerm_storage_account.main.name
}

# 3. Azure Storage Blob Container for Function App packages
resource "azurerm_storage_container" "app_package" {
  name                  = "app-package-functionappcreatedeployment"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private" 
}

# 4. Azure API Connection for Azure Queues
resource "azapi_resource" "msi-apiconnection" {
  type                      = "Microsoft.Web/connections@2016-06-01"
  name                      = "azurequeues_connection"
  location                  = azurerm_resource_group.automation.location
  parent_id                 = azurerm_resource_group.automation.id
  schema_validation_enabled = false

  body = {
    properties = {
      displayName        = "azurequeues_connection"
      api = {
        id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Web/locations/${azurerm_resource_group.automation.location}/managedApis/azurequeues"
        name = "azurequeues"
        type = "Microsoft.Web/locations/managedApis"
      }
      parameterValueSet = {
        name = "managedIdentityAuth"
        values = {}
      }
    }
  }

  tags = local.tags
}

# 5. Azure Logic App Workflow
resource "azurerm_logic_app_workflow" "proxy_logic_app" {
  name                = local.proxyLogicAppName
  resource_group_name = azurerm_resource_group.automation.name
  location            = azurerm_resource_group.automation.location
  enabled             = true
  lifecycle {
    ignore_changes = all
  }
  identity {
    type = "SystemAssigned"
  }
  tags = local.tags
  
} 

#Http trigger - needed for callback url
resource "azurerm_logic_app_trigger_http_request" "this" {
  name         = "When_a_HTTP_request_is_received"
  logic_app_id = azurerm_logic_app_workflow.proxy_logic_app.id
  schema       = <<SCHEMA
  {
  }
  SCHEMA
  lifecycle {
    ignore_changes = [schema]
  }
}

data "http" "remote_template" {
  url = "https://raw.githubusercontent.com/simon-vedder/projects/solution/terraform/order_vm/terraform/logicapp-saveordertoqueue.json"
}

resource "azurerm_resource_group_template_deployment" "logicapp-content" {
  name                = "${local.proxyLogicAppName}-${formatdate("YYYYMMDD-HHmmss", timestamp())}"
  resource_group_name = azurerm_resource_group.automation.name
  deployment_mode     = "Incremental"
  template_content    = data.http.remote_template.response_body
  parameters_content = jsonencode({
    "workflow_name"          = { value = azurerm_logic_app_workflow.proxy_logic_app.name } #do not change
    "connection_name"        = { value = azapi_resource.msi-apiconnection.name } #api connection for managed identity
    "storageaccount_name"    = { value = azurerm_storage_account.main.name }
    "queueName"              = { value = azurerm_storage_queue.order_queue.name }
  })
  depends_on = [
    azurerm_logic_app_workflow.proxy_logic_app,
    azurerm_storage_account.main
  ]
  lifecycle {
    ignore_changes = all
  }
}

# 6. Azure App Service Plan (for Function App)
resource "azurerm_service_plan" "function_app_plan" {
  name                = "${local.functionAppName}-ServicePlan"
  resource_group_name = azurerm_resource_group.automation.name
  location            = azurerm_resource_group.automation.location
  os_type             = "Windows" 
  sku_name            = "Y1"

  tags = local.tags
}

# 7. Azure Function App
resource "azurerm_windows_function_app" "create_deployment_function_app" {
  name                       = local.functionAppName
  resource_group_name = azurerm_resource_group.automation.name
  location            = azurerm_resource_group.automation.location
  service_plan_id        = azurerm_service_plan.function_app_plan.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  site_config {}
  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "AzureWebJobsDashboard"              = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.main.name};AccountKey=${azurerm_storage_account.main.primary_access_key}"
    "AzureWebJobsStorage"                = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.main.name};AccountKey=${azurerm_storage_account.main.primary_access_key}"
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.main.name};AccountKey=${azurerm_storage_account.main.primary_access_key}"
    "WEBSITE_CONTENTSHARE"               = lower("FunctionApp-CreateDeployment")
    "${azurerm_storage_account.main.name}__queueServiceUri" = "https://${azurerm_storage_account.main.name}.queue.core.windows.net"

    "FUNCTIONS_EXTENSION_VERSION" = "~4"
    "FUNCTIONS_WORKER_RUNTIME"    = "powershell"

    # Application-specific settings (empty values from ARM template)
    "keyVaultName"                = azurerm_key_vault.infra.name
    "resourceGroupName"           = azurerm_resource_group.virtualmachines.name
    "avdHostPoolName"             = azurerm_virtual_desktop_host_pool.vm.name
    "vnetName"                    = azurerm_virtual_network.vm.name
    "subnetName"                  = azurerm_subnet.vm.name
    "vmPrefix"                    = ""
    "domainName"                  = ""
    "domainUserName"              = ""
    "adminUsername"               = ""
    "ouPath"                      = ""
    "QueueName"                   = local.queueName
  }

  tags = local.tags
}