<#
.TITLE
    VM Order - AppFunction Handler

.SYNOPSIS
    React to new Azure Queue entry and start VM deployment

.DESCRIPTION
    This PowerShell script was designed to act as an app function with a queue trigger. It reads the queue message and the function apps environment variables to create a resource group deployment which is based on an ARM-Template.
    
.TAGS
    Automation, PowerShell, VirtualMachine, Order, Project

.MINROLE
    Key Vault Secrets User
    Contributor

.PERMISSIONS

.AUTHOR
    Simon Vedder

.VERSION
    1.0

.CHANGELOG
    1.0 - Initial release

.LASTUPDATE
    2025-06-08

.NOTES
    - Required Resources:
        - Key Vault = if you want to store your passwords securely. Use your existing one
        - Resource Group = the resource group where you want to store your VirtualMachines

.USAGE
  - Automatically get triggered by a new queue entry
  
#>
param($QueueItem, $TriggerMetadata)

# --- URL to my VM ARM Template ---
# Main resources: VirtualMachine, Network Security Group, Network Interface
# optional resources (depending on your order): Public IP, ADJoin Extension, EntraLogin Extension, AddSessionHost Extension
$vmDeploymentTemplateUrl = "https://raw.githubusercontent.com/simon-vedder/projects/refs/heads/main/order_vm/nestedTemplates/_vm.json"



try {
    # --- 1. JSON Input Processing ---
    Write-Host "Processing incoming JSON request..."

    $vmType = $QueueItem.vmType # Standard or avd
    $vmSize = $QueueItem.vmSize
    $publicIp = $QueueItem.publicIp
    $adJoin = $QueueItem.adJoin
    $entraExt = $QueueItem.entraExt
    $os = $QueueItem.os
    $application = $QueueItem.application
    
    # --- 2. Key Vault Read for Admin Password and AD Join Password ---
    Write-Host "Reading secrets from Key Vault: $env:keyVaultName"
    try {
        # Ensure your Azure Function's Managed Identity has 'Key Vault Secrets User' role on the Key Vault
        $adminPassword = (Get-AzKeyVaultSecret -VaultName $env:keyVaultName -Name "VmAdminPassword" -ErrorAction Stop).SecretValue # Replace with your actual secret names
        $domainPassword = (Get-AzKeyVaultSecret -VaultName $env:keyVaultName -Name "adJoinPassword" -ErrorAction Stop).SecretValue # Replace with your actual secret names
    }
    catch {
        Write-Host "Error reading secrets from Key Vault: $($PSItem.Exception.Message)" -ErrorAction Continue

        # Optional: More details for debugging
        Write-Host "Detailed error information:"
        Write-Host "  Exception Type: $($PSItem.Exception.GetType().FullName)"
        Write-Host "  Error Message: $($PSItem.Exception.Message)"
        Write-Host "  StackTrace: $($PSItem.ScriptStackTrace)" 
        
    }

    # --- 3. Deploy VM with ARM Template ---
    Write-Host "Initiating VM deployment using ARM template..."
    try {
        # Generate VMName
        if(!$application)
        {
            $vmName = "$($env:vmPrefix)-$(Get-Random -Maximum 99999)"
        }
        else {
            $vmName = "$($env:vmPrefix)-$($application)-$(Get-Random -Maximum 99999)"
        }
        
        # Generate template parameters
        $vmTemplateParameters = @{
            vmName = $vmName
            vmSize = $vmSize
            os = $os
            adminUsername = $env:adminUsername
            adminPassword = $adminPassword
            vnetName = $env:vnetName
            subnetName = $env:subnetName
            publicIpEnabled = $publicIp
            entraExt = $entraExt
        }

        # Add AVD required parameters
        if ($vmType -eq "avd") {
            # Get or renew Hostpool token
            try {
                $tokenObj = Get-AzWvdHostPoolRegistrationToken -ResourceGroupName $env:resourceGroupName -HostPoolName $env:avdHostPoolName
                if (-not $tokenObj -or -not $tokenObj.Token) {
                    throw "Token is missing"
                }
                $token = $tokenObj.Token
            }
            catch {
                $token = (New-AzWvdRegistrationInfo -ResourceGroupName $env:resourceGroupName -HostPoolName $env:avdHostPoolName -ExpirationTime ((Get-Date).AddDays(1))).Token
            }
            $vmTemplateParameters.Add("avdExt", $true)
            $vmTemplateParameters.Add("avdHostPoolName", $env:avdHostPoolName)
            $vmTemplateParameters.Add("avdRegistrationToken", $token)
        }

        # Add ADJoin required parameters
        if($adJoin -eq $true)
        {
            $vmTemplateParameters.Add("adJoin", $adJoin)
            $vmTemplateParameters.Add("domainName", $env:domainName)
            $vmTemplateParameters.Add("ouPath", $env:ouPath)
            $vmTemplateParameters.Add("domainUserName", $env:domainUserName)
            $vmTemplateParameters.Add("domainPassword", $domainPassword)
        }

        # Generate deploymentName
        $deploymentName = "vm-order-$(Get-Date -Format 'yyyyMMddHHmmss')-$(Get-Random)"

        # Start template deployment
        New-AzResourceGroupDeployment `
            -ResourceGroupName $env:resourceGroupName `
            -TemplateUri $vmDeploymentTemplateUrl `
            -TemplateParameterObject $vmTemplateParameters `
            -Name $deploymentName `
            -Force `
            -ErrorAction Stop

        Write-Host "VM deployment '$deploymentName' initiated successfully."
    }
    catch {
        Write-Host "Error during VM deployment: $($PSItem.Exception.Message)" -ErrorAction Continue

        # Optional: More details for debugging
        Write-Host "Detailed error information:"
        Write-Host "  Exception Type: $($PSItem.Exception.GetType().FullName)"
        Write-Host "  Error Message: $($PSItem.Exception.Message)"
        Write-Host "  StackTrace: $($PSItem.ScriptStackTrace)" 
    }

}
catch {
    Write-Host "An unexpected error occurred"
}