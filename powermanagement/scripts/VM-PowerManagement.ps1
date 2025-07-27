<#
.SYNOPSIS
    Automated Azure VM power management script for scheduled start/stop operations.

.DESCRIPTION
    This PowerShell script provides automated power management for Azure Virtual Machines across multiple subscriptions.
    It supports scheduled start and stop operations with flexible exclusion rules using VM tags and day-of-week filtering.
    The script is designed to run in Azure Automation Runbooks using Managed Identity authentication.

.PARAMETER Action
    Specifies the power action to perform on VMs.
    Valid values: "Start", "Stop"
    This parameter is mandatory.

.PARAMETER SubscriptionIds
    Optional array of specific Azure Subscription IDs to process.
    If not provided, the script will process all subscriptions accessible to the Managed Identity.
    Example: @("12345678-1234-1234-1234-123456789012", "87654321-4321-4321-4321-210987654321")

.PARAMETER AutoCreateTags
    Optional switch to automatically create missing power management tags with default values.
    Default: $true

.NOTES
    File Name      : AzVM-PowerManagement.ps1
    Author         : Simon Vedder
    Date           : 26.07.2025
    Prerequisite   : Azure PowerShell modules, Managed Identity with appropriate permissions
    
    Required Permissions:
    - Virtual Machine Contributor role on target subscriptions
    - Or Contributor role on target subscriptions
    - Or Custom Role with the following permission:
        "Microsoft.Compute/virtualMachines/read",
        "Microsoft.Compute/virtualMachines/write",
        "Microsoft.Network/networkInterfaces/join/action",
        "Microsoft.Compute/disks/write",
        "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
        "Microsoft.Compute/virtualMachines/start/action",
        "Microsoft.Compute/virtualMachines/deallocate/action"
    
    VM Tag Controls:
    - AutoShutdown-Exclude: "true" - Permanently exclude VM from power management
    - AutoShutdown-SkipUntil: "yyyy-mm-dd" - Skip VM until specified date
    - AutoShutdown-ExcludeOn: "yyyy-mm-dd" - Exclude VM on specific date only
    - AutoShutdown-ExcludeDays: "Monday,Tuesday,Wednesday" - Exclude VM on specific weekdays

.EXAMPLE
    # Stop all VMs across all subscriptions
    .\Azure-VM-PowerManagement.ps1 -Action "Stop"

.EXAMPLE
    # Start VMs in specific subscriptions only
    .\Azure-VM-PowerManagement.ps1 -Action "Start" -SubscriptionIds @("12345678-1234-1234-1234-123456789012")

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    Console output with detailed logging of all operations performed.
    Returns summary statistics of processed, actioned, skipped, and error VMs.

.LINK
    https://docs.microsoft.com/en-us/azure/automation/
    https://docs.microsoft.com/en-us/azure/virtual-machines/
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Start", "Stop")]
    [string]$Action,
    
    [Parameter(Mandatory=$false)]
    [string[]]$SubscriptionIds = @(),
    
    [Parameter(Mandatory=$false)]
    [bool]$AutoCreateTags = $true
)

# Function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] [$Level] $Message"
}

# Function to ensure VM has required power management tags
function Ensure-PowerManagementTags {
    param(
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [DateTime]$CurrentDate
    )
    
    if (-not $AutoCreateTags) {
        return $VM.Tags
    }
    
    $vmTags = $VM.Tags
    if ($null -eq $vmTags) {
        $vmTags = @{}
    }
    
    $tagsToAdd = @{}
    $tagAdded = $false
    
    # Check and add missing tags with default values
    if (-not $vmTags.ContainsKey("AutoShutdown-Exclude")) {
        $tagsToAdd["AutoShutdown-Exclude"] = "false"
        $tagAdded = $true
    }
    
    if (-not $vmTags.ContainsKey("AutoShutdown-SkipUntil")) {
        $tagsToAdd["AutoShutdown-SkipUntil"] = ""
        $tagAdded = $true
    }
    
    if (-not $vmTags.ContainsKey("AutoShutdown-ExcludeOn")) {
        $tagsToAdd["AutoShutdown-ExcludeOn"] = $CurrentDate.ToString("yyyy-MM-dd") #to exclude it at the date when tags get set - otherwise all your existing VMs will get stopped or started during this process
        $tagAdded = $true
    }
    
    if (-not $vmTags.ContainsKey("AutoShutdown-ExcludeDays")) {
        $tagsToAdd["AutoShutdown-ExcludeDays"] = ""
        $tagAdded = $true
    }
    
    # Add missing tags to VM
    if ($tagAdded) {
        try {
            Write-Log "VM $($VM.Name): Adding missing power management tags..."
            
            # Merge existing tags with new tags
            foreach ($key in $tagsToAdd.Keys) {
                $vmTags[$key] = $tagsToAdd[$key]
            }
            
            # Update VM tags
            Update-AzTag -ResourceId $VM.Id -Tag $vmTags -Operation Merge -ErrorAction Stop
            Write-Log "VM $($VM.Name): Successfully added missing tags: $($tagsToAdd.Keys -join ', ')"
        }
        catch {
            Write-Log "VM $($VM.Name): Failed to add tags: $($_.Exception.Message)" "WARNING"
        }
    }
}

# Main Function
try {
    Write-Log "Starting VM Power Management Script - Action: $Action"
    Write-Log "Auto-create missing tags: $AutoCreateTags"
    
    # check date and weekday
    $currentDate = Get-Date
    $currentDayOfWeek = $currentDate.DayOfWeek.ToString()
    
    Write-Log "Current Date: $($currentDate.ToString('yyyy-MM-dd')), Day: $currentDayOfWeek"
    
    # Login with managed identity
    Write-Log "Connecting to Azure using Managed Identity..."
    try {
        $null = Connect-AzAccount -Identity -ErrorAction Stop
        Write-Log "Successfully connected to Azure"
    }
    catch {
        Write-Log "Failed to connect to Azure: $($_.Exception.Message)" "ERROR"
        throw
    }
    
    # Get subscription context
    $context = Get-AzContext
    Write-Log "Initially connected to Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
    
    # Set subscription
    if ($SubscriptionIds.Count -eq 0) {
        Write-Log "No specific Subscriptions specified. Getting all available Subscriptions..."
        $allSubscriptions = Get-AzSubscription
        $targetSubscriptions = $allSubscriptions
        Write-Log "Found $($allSubscriptions.Count) available Subscriptions"
    } else {
        Write-Log "Processing specific Subscriptions: $($SubscriptionIds -join ', ')"
        $targetSubscriptions = @()
        foreach ($subId in $SubscriptionIds) {
            try {
                $sub = Get-AzSubscription -SubscriptionId $subId -ErrorAction Stop
                $targetSubscriptions += $sub
            }
            catch {
                Write-Log "Could not find Subscription: $subId - Error: $($_.Exception.Message)" "ERROR"
            }
        }
    }
    
    Write-Log "Target Subscriptions: $($targetSubscriptions.Count)"
    
    # Statistics
    $processedVMs = 0
    $skippedVMs = 0
    $errorVMs = 0
    $actionedVMs = 0
    $tagsAddedVMs = 0
    
    
    foreach ($subscription in $targetSubscriptions) {
        Write-Log "Processing Subscription: $($subscription.Name) ($($subscription.Id))"
        
        try {
            # Switch subscriptions
            $null = Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop
            Write-Log "Switched to Subscription: $($subscription.Name)"
            
            # Get VMs of this subscription
            $vms = Get-AzVM -ErrorAction Stop
            Write-Log "Found $($vms.Count) VMs in Subscription: $($subscription.Name)"
            
            foreach ($vm in $vms) {
                $processedVMs++
                $vmName = $vm.Name
                $vmResourceGroup = $vm.ResourceGroupName
                
                Write-Log "Processing VM: $vmName (RG: $vmResourceGroup)"
                
                # Ensure VM has required power management tags
                Ensure-PowerManagementTags -VM $vm -CurrentDate $currentDate
                
                # Get VM Tags
                $vmTags = $vm.Tags
                if ($null -eq $vmTags) {
                    $vmTags = @{}
                }
                
                # Check Skip-Tag (AutoShutdown-Exclude)
                if ($vmTags.ContainsKey("AutoShutdown-Exclude") -and $vmTags["AutoShutdown-Exclude"] -eq "true") {
                    Write-Log "VM $vmName : Skipped due to AutoShutdown-Exclude tag" "WARNING"
                    $skippedVMs++
                    continue
                }
                
                # Check Weekday-based exclusion
                if ($vmTags.ContainsKey("AutoShutdown-ExcludeDays") -and $vmTags["AutoShutdown-ExcludeDays"] -ne "") {
                    $excludedDaysValue = $vmTags["AutoShutdown-ExcludeDays"]
                    $vmExcludedDays = $excludedDaysValue -split ","
                    $vmExcludedDays = $vmExcludedDays | ForEach-Object { $_.Trim() }
                    
                    if ($vmExcludedDays -contains $currentDayOfWeek) {
                        Write-Log "VM $vmName : Skipped due to AutoShutdown-ExcludeDays tag (Today: $currentDayOfWeek)" "WARNING"
                        $skippedVMs++
                        continue
                    }
                }
                
                # Date-based exlusion
                $skipUntilDate = $null
                $excludeDate = $null
                
                # Check Skip-Until Tag (temporary skip until the entered date)
                if ($vmTags.ContainsKey("AutoShutdown-SkipUntil") -and $vmTags["AutoShutdown-SkipUntil"] -ne "") {
                    $skipUntilValue = $vmTags["AutoShutdown-SkipUntil"]
                    try {
                        $skipUntilDate = [DateTime]::ParseExact($skipUntilValue, "yyyy-MM-dd", $null)
                        if ($currentDate.Date -le $skipUntilDate.Date) {
                            Write-Log "VM $vmName : Skipped until $($skipUntilDate.ToString('yyyy-MM-dd'))" "WARNING"
                            $skippedVMs++
                            continue
                        } else {
                            Write-Log "VM $vmName : SkipUntil date ($($skipUntilDate.ToString('yyyy-MM-dd'))) has passed, processing normally"
                        }
                    }
                    catch {
                        Write-Log "VM $vmName : Invalid SkipUntil date format: $skipUntilValue" "WARNING"
                    }
                }
                
                # Check Exclude-On Tag (exclusion at a specific date)
                if ($vmTags.ContainsKey("AutoShutdown-ExcludeOn") -and $vmTags["AutoShutdown-ExcludeOn"] -ne "") {
                    $excludeOnValue = $vmTags["AutoShutdown-ExcludeOn"]
                    try {
                        $excludeDate = [DateTime]::ParseExact($excludeOnValue, "yyyy-MM-dd", $null)
                        if ($currentDate.Date -eq $excludeDate.Date) {
                            Write-Log "VM $vmName : Excluded today due to ExcludeOn tag ($($excludeDate.ToString('yyyy-MM-dd')))" "WARNING"
                            $skippedVMs++
                            continue
                        }
                    }
                    catch {
                        Write-Log "VM $vmName : Invalid ExcludeOn date format: $excludeOnValue" "WARNING"
                    }
                }
                
                # Get VM State
                try {
                    $vmStatus = Get-AzVM -ResourceGroupName $vmResourceGroup -Name $vmName -Status -ErrorAction Stop
                    $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).Code
                    
                    Write-Log "VM $vmName : Current state: $powerState"
                    
                    # Action based on the specification and current state 
                    $shouldPerformAction = $false
                    
                    if ($Action -eq "Stop") {
                        if ($powerState -eq "PowerState/running") {
                            $shouldPerformAction = $true
                        } else {
                            Write-Log "VM $vmName : Already stopped or in transition, skipping"
                        }
                    } elseif ($Action -eq "Start") {
                        if ($powerState -eq "PowerState/deallocated" -or $powerState -eq "PowerState/stopped") {
                            $shouldPerformAction = $true
                        } else {
                            Write-Log "VM $vmName : Already running or in transition, skipping"
                        }
                    }
                    
                    if ($shouldPerformAction) {
                        Write-Log "VM $vmName : Performing $Action action..."
                        
                        if ($Action -eq "Stop") {
                            $result = Stop-AzVM -ResourceGroupName $vmResourceGroup -Name $vmName -NoWait -Force -ErrorAction Stop
                            Write-Log "VM $vmName : Successfully stopped/deallocated"
                        } elseif ($Action -eq "Start") {
                            $result = Start-AzVM -ResourceGroupName $vmResourceGroup -Name $vmName -NoWait -ErrorAction Stop
                            Write-Log "VM $vmName : Successfully started"
                        }
                        
                        $actionedVMs++
                    } else {
                        $skippedVMs++
                    }
                }
                catch {
                    Write-Log "VM $vmName : Error during $Action action: $($_.Exception.Message)" "ERROR"
                    $errorVMs++
                }
            }
        }
        catch {
            Write-Log "Error processing Subscription $($subscription.Name): $($_.Exception.Message)" "ERROR"
            $errorVMs++
        }
    }
    
    # Summary
    Write-Log "=== SUMMARY ===" "INFO"
    Write-Log "Total VMs processed: $processedVMs" "INFO"
    Write-Log "VMs actioned ($Action): $actionedVMs" "INFO"
    Write-Log "VMs skipped: $skippedVMs" "INFO"
    Write-Log "VMs with errors: $errorVMs" "INFO"
    if ($AutoCreateTags) {
        Write-Log "VMs with tags auto-created: Check individual VM logs above" "INFO"
    }
    
    Write-Log "Script completed successfully" "INFO"
}
catch {
    Write-Log "Script failed with error: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.Exception.StackTrace)" "ERROR"
    throw
}