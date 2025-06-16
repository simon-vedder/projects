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
    queueStorageAccountName = "vmorderstorageaccount"
    queueName = "vmorderqueue"
    proxyLogicAppName = "LogicApp-SaveOrderToQueue"
    functionAppName = "FunctionApp-CreateDeployment1"

    #infrastructure
    infrastructureRGName = "VMOrderInfrastructure"
    keyVaultName = "KeyVault-VMOrder2"
    webStorageAccount = "vmorderwebfrontendhtml"

    #virtualmachines
    virtualmachinesRGName = "VMOrderVirtualMachines"
    hostpoolName = "Personal-HP"
    vnetName = "VMOrder-VNet"
    subnetName = "default"
    
}