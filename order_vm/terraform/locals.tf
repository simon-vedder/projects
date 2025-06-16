locals {
    #general
    location = "westeurope"
    tags = {
        Author = "Simon Vedder"
        Contact = "info@simonvedder.com"
        Project = "VMOrder"
        ManagedBy = "ARMTemplate"
    }

    #automation     
    automationRGName = "VMOrderAutomation"
    queueStorageAccountName = ""
    queueName = ""
    proxyLogicAppName = ""
    functionAppName = ""

    #infrastructure
    infrastructureRGName = "VMOrderInfrastructure"
    keyVaultName = ""
    webStorageAccount = ""

    #virtualmachines
    virtualmachinesRGName = "VMOrderVirtualMachines"
    hostpoolName = ""
    vnetName = ""
    subnetName = ""
    
}