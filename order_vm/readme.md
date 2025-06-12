# Project: Order VM

## Recommended Seperation
- Resourcegroups:
    - OrderAutomations (whole Automation - LogicApp, FunctionApp, Queue Storage Account)
    - OrderInfrastructure (optional - Storage Account for WebFrontend, Azure KeyVault)
    - OrderVirtualMachines (optional - AVD Hostpool, VirtualNetwork & Subnet)

## Required Resources:
- Logic App 
    - Trigger: HTTP
    - As proxy to save incoming orders in Azure Queue
    - API Connections
- Storage Account 
    - Queue Service
- Function App
    - Read queue message and start VM deployment
    - Upload content via zip deployment
        az functionapp deployment source config-zip --resource-group OrderAutomations --name FunctionApp-CreateDeployment --src ./run.zip

- Virtual Network & Subnet - *
- Hostpool for AVD - *
*same RG - can be configured to exist in a different RG via _vm.json

## Required permissions:
- Logic App Managed Identity:
    - Storage Queue Data Contributor - Scope: Queue Storage Account
    - Directory Reader (Entra) - Validate UPN (manual)
- Function App Managed Identity:
    - Storage Blob Data Owner - Scope: Storage Account
    - Key Vault Secrets User - Scope: Key Vault with Password Secrets (manual)
    - Contributor - Scope: Resource Group for VirtualMachines (manual)



## "optional" Resources
These resources are required to have a working solution. 
I call them optional because I assume that you already got those resources in your working environment.

Resources:
- web / programmatic solution: 
    - I use a storage account with static html web hosting 
    - I upload the html code in this blob storage
- azure keyvault
    - storing passwords for:
        - Local VM Admin
        - AD Domain Join User