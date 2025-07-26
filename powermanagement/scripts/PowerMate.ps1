 <#
.SYNOPSIS
    PowerMate - Interactive GUI tool for Azure VM auto-shutdown management and manual deallocation.

.DESCRIPTION
    PowerMate is a Windows Presentation Foundation (WPF) based PowerShell GUI application that provides an intuitive
    interface for managing Azure Virtual Machine auto-shutdown settings and performing manual VM operations.
    The tool runs directly on Azure VMs using User Assigned Managed Identity authentication and provides real-time status
    monitoring of auto-shutdown exclusion tags and manual control capabilities.
    This is an addition to the VM-PowerManagement created by me - Simon Vedder.

    Key Features:
    - Real-time display of current auto-shutdown status
    - Visual indication of active exclusion tags and their effects
    - One-click daily skip functionality for temporary exclusions
    - Manual VM deallocation with confirmation dialogs
    - Automatic refresh of VM tag status
    - Clear management of temporary skip tags

.PARAMETER None
    This GUI application does not accept command-line parameters.
    All configuration is handled through the interactive interface.

.NOTES
    File Name      : PowerMate-GUI.ps1
    Author         : Simon Vedder
    Date           : 26.07.2025
    Prerequisite   : Azure VM with Managed Identity enabled, PowerShell 5.1+ (Recommend 7.2), .NET Framework 4.5+
    
    Required Permissions:
    - Virtual Machine Contributor role on the VM's resource group
    - Or Contributor role on the VM's subscription
    - Or Custom Role with the following permission:
        "Microsoft.Compute/virtualMachines/read",
        "Microsoft.Compute/virtualMachines/write",
        "Microsoft.Compute/virtualMachines/deallocate/action",
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Resources/tags/read",
        "Microsoft.Resources/tags/write"
    
    Supported VM Tag Controls:
    - AutoShutdown-Exclude: "true" - Permanently exclude VM from auto-shutdown (Admin-level)
    - AutoShutdown-SkipUntil: "yyyy-mm-dd" - Skip VM until specified date (Admin-level)
    - AutoShutdown-ExcludeOn: "yyyy-mm-dd" - Exclude VM on specific date only (User-manageable)
    - AutoShutdown-ExcludeDays: "Monday,Tuesday,Wednesday" - Exclude VM on specific weekdays (Admin-level)

    GUI Components:
    - Status Display: Shows current auto-shutdown status with color-coded indicators
    - Tag Information: Displays active exclusion tags and their values
    - Action Buttons: "Deallocate Now" and "Skip for Today" for immediate actions
    - Management Buttons: "Refresh Status" and "Clear Today Skip" for tag management

.EXAMPLE
    # Run the PowerMate GUI application
    - .\PowerMate-GUI.ps1
    - Or compile to Exe with PS2EXE and run the exe

    Description:
    Launches the PowerMate GUI interface. The application will automatically:
    - Retrieve VM metadata using Azure Instance Metadata Service
    - Authenticate using the VM's Managed Identity
    - Display current auto-shutdown status and active tags
    - Enable appropriate action buttons based on current state

.EXAMPLE
    # Typical workflow - Skip VM shutdown for today
    1. Launch PowerMate GUI
    2. Review current status (shows "VM will shut down at 21:00 today")
    3. Click "Skip for Today" button
    4. Status updates to "VM shutdown is DISABLED for today"
    5. "Skip for Today" button becomes disabled, "Clear Today Skip" becomes enabled

.EXAMPLE
    # Emergency workflow - Immediate VM deallocation
    1. Launch PowerMate GUI
    2. Click "Deallocate Now" button
    3. Confirm action in the warning dialog
    4. VM begins deallocation process immediately
    5. Status updates to show deallocation request sent

.INPUTS
    None. This GUI application uses Azure Instance Metadata Service and Managed Identity
    for automatic configuration and authentication.

.OUTPUTS
    Interactive Windows GUI with the following elements:
    - Real-time status display with color-coded indicators:
      * Red: VM scheduled for shutdown
      * Green: VM excluded for today
      * Orange: VM excluded by administrator
    - Tag information panel showing active exclusion rules
    - Action buttons for immediate operations
    - Confirmation dialogs for destructive actions

.FUNCTIONALITY
    Status Indicators:
    - ❌ Red: "VM will shut down at 21:00 today" - No exclusions active
    - ✅ Green: "VM shutdown is DISABLED for today" - Temporary daily skip active
    - 🔒 Orange: "VM shutdown is DISABLED by administrator" - Permanent/admin exclusions

    Button States:
    - "Skip for Today": Enabled when no daily skip is active
    - "Clear Today Skip": Enabled when daily skip tag exists
    - "Deallocate Now": Always enabled (with confirmation)
    - "Refresh Status": Always enabled for manual status updates

    Error Handling:
    - Displays user-friendly error messages for authentication failures
    - Shows specific error details for Azure API call failures
    - Gracefully handles network connectivity issues
    - Provides clear feedback for all user actions

.SECURITY
    Authentication Method: Azure Managed Identity (no stored credentials)
    Required VM Configuration: System-assigned or User-assigned Managed Identity enabled
    Network Requirements: Access to Azure Instance Metadata Service (169.254.169.254)
    API Permissions: Read/Write access to VM resource tags, VM deallocation permissions

.LINK
    https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/
    https://docs.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service
    https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/tag-resources
#>


Add-Type -AssemblyName PresentationFramework

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PowerMate - Azure VM Deallocate Tool" Height="480" Width="480" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" Background="#f4f4f4" FontFamily="Segoe UI">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <TextBlock Text="PowerMate - Azure VM Deallocate Tool" FontSize="18" FontWeight="Bold" Foreground="#333"
                   HorizontalAlignment="Center" Margin="0,0,0,15" Grid.Row="0"/>

        <!-- Current Status Section -->
        <Border Grid.Row="1" Background="White" CornerRadius="8" Padding="10" Margin="0,0,0,10" BorderBrush="#ddd" BorderThickness="1">
            <StackPanel>
                <TextBlock Text="Current Status:" FontWeight="Bold" Foreground="#333" Margin="0,0,0,5"/>
                <TextBlock x:Name="txtStatus" Text="Loading status..." TextWrapping="Wrap" Foreground="#333"/>
            </StackPanel>
        </Border>

        <!-- Tag Information Section -->
        <Border Grid.Row="2" Background="White" CornerRadius="8" Padding="10" Margin="0,0,0,10" BorderBrush="#ddd" BorderThickness="1">
            <StackPanel>
                <TextBlock Text="Current VM Tags:" FontWeight="Bold" Foreground="#333" Margin="0,0,0,5"/>
                <TextBlock x:Name="txtTagInfo" Text="Loading tags..." TextWrapping="Wrap" Foreground="#666" FontSize="11"/>
            </StackPanel>
        </Border>

        <!-- Action Buttons -->
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,5,0,10">
            <Button x:Name="btnDeallocateNow" Content="Deallocate Now" Width="140" Margin="10"
                    Background="#dc3545" Foreground="White" BorderThickness="0" Padding="8" FontWeight="SemiBold"
                    Cursor="Hand">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="8"/>
                    </Style>
                </Button.Resources>
            </Button>

            <Button x:Name="btnSkipToday" Content="Skip for Today" Width="140" Margin="10"
                    Background="#28a745" Foreground="White" BorderThickness="0" Padding="8" FontWeight="SemiBold"
                    Cursor="Hand">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="8"/>
                    </Style>
                </Button.Resources>
            </Button>
        </StackPanel>

        <!-- Management Buttons -->
        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,10">
            <Button x:Name="btnRefresh" Content="Refresh Status" Width="140" Margin="10"
                    Background="#6c757d" Foreground="White" BorderThickness="0" Padding="8" FontWeight="SemiBold"
                    Cursor="Hand">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="8"/>
                    </Style>
                </Button.Resources>
            </Button>

            <Button x:Name="btnClearToday" Content="Clear Today Skip" Width="140" Margin="10"
                    Background="#17a2b8" Foreground="White" BorderThickness="0" Padding="8" FontWeight="SemiBold"
                    Cursor="Hand">
                <Button.Resources>
                    <Style TargetType="Border">
                        <Setter Property="CornerRadius" Value="8"/>
                    </Style>
                </Button.Resources>
            </Button>
        </StackPanel>

        <!-- Info Text -->
        <TextBlock Text="Note: VM is scheduled to shut down daily at 21:00 unless excluded by tags."
                   Grid.Row="5" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Center"
                   FontStyle="Italic" Foreground="Gray" Margin="0,10,0,5"/>

        <!-- Author Info -->
        <TextBlock Text="Created by Simon Vedder"
                   Grid.Row="6" TextWrapping="Wrap" HorizontalAlignment="Center" VerticalAlignment="Bottom"
                   FontStyle="Italic" Foreground="#999" FontSize="10" Margin="0,5,0,5"/>
    </Grid>
</Window>
"@

# Load XAML
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Controls
$btnDeallocateNow = $window.FindName("btnDeallocateNow")
$btnSkipToday = $window.FindName("btnSkipToday")
$btnClearToday = $window.FindName("btnClearToday")
$btnRefresh = $window.FindName("btnRefresh")
$txtStatus = $window.FindName("txtStatus")
$txtTagInfo = $window.FindName("txtTagInfo")

# Global variables
$global:vmInfo = $null

function Get-AzureAccessToken {
    try {
        $tokenResponse = Invoke-RestMethod -Method Get -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/" -Headers @{Metadata="true"} -ErrorAction Stop
        return $tokenResponse.access_token
    } catch {
        throw "Failed to get Managed Identity token. Is the Managed Identity enabled on this VM?"
    }
}

function Get-VMInfo {
    $metadataUrl = "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"
    $headers = @{Metadata="true"}
    try {
        $meta = Invoke-RestMethod -Uri $metadataUrl -Headers $headers -ErrorAction Stop
        return @{
            SubscriptionId = $meta.subscriptionId
            ResourceGroupName = $meta.resourceGroupName
            VMName = $meta.name
        }
    } catch {
        throw "Failed to get VM metadata."
    }
}

function Get-VMTags {
    param (
        [string]$subscriptionId,
        [string]$resourceGroupName,
        [string]$vmName
    )

    $token = Get-AzureAccessToken
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$($vmName)?api-version=2021-07-01"

    try {
        $vmInfo = Invoke-RestMethod -Method Get -Uri $uri -Headers @{Authorization = "Bearer $token"} -ErrorAction Stop
        return $vmInfo.tags
    } catch {
        throw "Failed to read VM tags from Azure."
    }
}

function Set-VMTag {
    param (
        [string]$subscriptionId,
        [string]$resourceGroupName,
        [string]$vmName,
        [string]$tagKey,
        [string]$tagValue
    )

    $token = Get-AzureAccessToken
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$($vmName)?api-version=2021-07-01"

    $vmInfo = Invoke-RestMethod -Method Get -Uri $uri -Headers @{Authorization = "Bearer $token"} -ErrorAction Stop
    $tags = @{}
    if ($vmInfo.tags) {
        $tags = $vmInfo.tags.PSObject.Copy()
    }
    $tags.$tagKey = $tagValue
    $body = @{ tags = $tags } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Method Patch -Uri $uri -Headers @{
        Authorization = "Bearer $token"
        "Content-Type" = "application/json"
    } -Body $body -ErrorAction Stop

    return $tagValue
}

function Remove-VMTag {
    param (
        [string]$subscriptionId,
        [string]$resourceGroupName,
        [string]$vmName,
        [string]$tagKey
    )

    $token = Get-AzureAccessToken
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$($vmName)?api-version=2021-07-01"

    $vmInfo = Invoke-RestMethod -Method Get -Uri $uri -Headers @{Authorization = "Bearer $token"} -ErrorAction Stop
    $tags = @{}
    if ($vmInfo.tags) {
        $tags = $vmInfo.tags.PSObject.Copy()
    }
    
    if ($tags.$tagKey) {
        $tags.PSObject.Properties.Remove($tagKey)
    }
    
    $body = @{ tags = $tags } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Method Patch -Uri $uri -Headers @{
        Authorization = "Bearer $token"
        "Content-Type" = "application/json"
    } -Body $body -ErrorAction Stop
}

function Deallocate-VMNow {
    param (
        [string]$subscriptionId,
        [string]$resourceGroupName,
        [string]$vmName
    )

    $token = Get-AzureAccessToken
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/deallocate?api-version=2021-07-01"

    Invoke-RestMethod -Method Post -Uri $uri -Headers @{
        Authorization = "Bearer $token"
    } -ErrorAction Stop
}

function Update-StatusDisplay {
    try {
        $tags = Get-VMTags -subscriptionId $global:vmInfo.SubscriptionId -resourceGroupName $global:vmInfo.ResourceGroupName -vmName $global:vmInfo.VMName
        $today = (Get-Date).ToString("yyyy-MM-dd")
        $currentDayOfWeek = (Get-Date).DayOfWeek.ToString()
        
        # Check all exclusion conditions
        $isExcluded = $false
        $exclusionReason = ""
        $exclusionType = ""
        
        # Permanent exclusion (highest priority)
        if ($tags."AutoShutdown-Exclude" -eq "true") {
            $isExcluded = $true
            $exclusionReason = "VM is permanently excluded from auto-shutdown"
            $exclusionType = "PERMANENT"
        }
        # Skip until date
        elseif ($tags."AutoShutdown-SkipUntil") {
            try {
                $skipUntilDate = [DateTime]::ParseExact($tags."AutoShutdown-SkipUntil", "yyyy-MM-dd", $null)
                if ((Get-Date).Date -le $skipUntilDate.Date) {
                    $isExcluded = $true
                    $exclusionReason = "VM is skipped until $($tags.'AutoShutdown-SkipUntil')"
                    $exclusionType = "ADMIN_SKIP"
                }
            }
            catch {
                # Invalid date format
            }
        }
        # Exclude on specific days
        elseif ($tags."AutoShutdown-ExcludeDays") {
            $excludedDays = $tags."AutoShutdown-ExcludeDays" -split ","
            $excludedDays = $excludedDays | ForEach-Object { $_.Trim() }
            if ($excludedDays -contains $currentDayOfWeek) {
                $isExcluded = $true
                $exclusionReason = "VM is excluded on $currentDayOfWeek (Weekday exclusion)"
                $exclusionType = "WEEKDAY"
            }
        }
        # Exclude on specific date (today)
        elseif ($tags."AutoShutdown-ExcludeOn" -eq $today) {
            $isExcluded = $true
            $exclusionReason = "VM is excluded for today ($today)"
            $exclusionType = "TODAY"
        }
        
        # Update status text with appropriate styling
        if ($isExcluded) {
            if ($exclusionType -eq "TODAY") {
                $txtStatus.Text = "✅ VM shutdown is DISABLED for today`n$exclusionReason"
                $txtStatus.Foreground = 'Green'
            }
            elseif ($exclusionType -eq "PERMANENT" -or $exclusionType -eq "ADMIN_SKIP" -or $exclusionType -eq "WEEKDAY") {
                $txtStatus.Text = "🔒 VM shutdown is DISABLED by administrator`n$exclusionReason"
                $txtStatus.Foreground = 'Orange'
            }
        } else {
            $txtStatus.Text = "❌ VM will shut down at 21:00 today`nNo exclusion tags active"
            $txtStatus.Foreground = 'DarkRed'
        }
        
        # Update tag info - only show relevant information
        $tagDisplay = ""
        if ($tags) {
            if ($tags."AutoShutdown-Exclude" -eq "true") {
                $tagDisplay += "⚠️ Permanent Exclusion: Active`n"
            }
            if ($tags."AutoShutdown-SkipUntil") {
                $tagDisplay += "📅 Skip Until: $($tags.'AutoShutdown-SkipUntil')`n"
            }
            if ($tags."AutoShutdown-ExcludeDays") {
                $tagDisplay += "📆 Excluded Days: $($tags.'AutoShutdown-ExcludeDays')`n"
            }
            if ($tags."AutoShutdown-ExcludeOn") {
                $tagDisplay += "🗓️ Today Skip: $($tags.'AutoShutdown-ExcludeOn')`n"
            }
        }
        
        if ($tagDisplay) {
            $txtTagInfo.Text = $tagDisplay.TrimEnd()
        } else {
            $txtTagInfo.Text = "No AutoShutdown exclusions set"
        }
        
        # Enable/disable buttons based on current state
        if ($tags."AutoShutdown-ExcludeOn" -eq $today) {
            $btnClearToday.IsEnabled = $true
            $btnSkipToday.IsEnabled = $false
        } else {
            $btnClearToday.IsEnabled = $false
            $btnSkipToday.IsEnabled = $true
        }
        
    }
    catch {
        $txtStatus.Text = "⚠️ Error checking status: $_"
        $txtStatus.Foreground = 'DarkRed'
        $txtTagInfo.Text = "Error loading tags"
    }
}

# Initialize
try {
    $global:vmInfo = Get-VMInfo
    Update-StatusDisplay
}
catch {
    $txtStatus.Text = "⚠️ Error initializing: $_"
    $txtStatus.Foreground = 'DarkRed'
}

# Button Events
$btnSkipToday.Add_Click({
    $txtStatus.Text = "⏳ Setting skip tag for today..."
    $txtStatus.Foreground = 'Black'
    try {
        $today = (Get-Date).ToString("yyyy-MM-dd")
        Set-VMTag -subscriptionId $global:vmInfo.SubscriptionId -resourceGroupName $global:vmInfo.ResourceGroupName -vmName $global:vmInfo.VMName -tagKey "AutoShutdown-ExcludeOn" -tagValue $today
        Update-StatusDisplay
    }
    catch {
        $txtStatus.Text = "❌ Error setting skip tag: $_"
        $txtStatus.Foreground = 'DarkRed'
    }
})

$btnClearToday.Add_Click({
    $confirmation = [System.Windows.MessageBox]::Show(
        "Are you sure you want to clear the skip tag for today? The VM will shutdown at 21:00.",
        "Confirm Clear Today Skip",
        "YesNo",
        "Question"
    )

    if ($confirmation -eq "Yes") {
        $txtStatus.Text = "⏳ Clearing today's skip tag..."
        $txtStatus.Foreground = 'Black'
        try {
            Set-VMTag -subscriptionId $global:vmInfo.SubscriptionId -resourceGroupName $global:vmInfo.ResourceGroupName -vmName $global:vmInfo.VMName -tagKey "AutoShutdown-ExcludeOn" -tagValue ""
            Update-StatusDisplay
        }
        catch {
            $txtStatus.Text = "❌ Error clearing skip tag: $_"
            $txtStatus.Foreground = 'DarkRed'
        }
    }
})

$btnDeallocateNow.Add_Click({
    $confirmation = [System.Windows.MessageBox]::Show(
        "Are you sure you want to deallocate this VM now?",
        "Confirm Deallocation",
        "YesNo",
        "Warning"
    )

    if ($confirmation -eq "Yes") {
        $txtStatus.Text = "⏳ Deallocating VM now..."
        $txtStatus.Foreground = 'Black'
        try {
            Deallocate-VMNow -subscriptionId $global:vmInfo.SubscriptionId -resourceGroupName $global:vmInfo.ResourceGroupName -vmName $global:vmInfo.VMName
            $txtStatus.Text = "✅ Deallocate request sent successfully."
            $txtStatus.Foreground = 'Green'
        }
        catch {
            $txtStatus.Text = "❌ Error deallocating VM: $_"
            $txtStatus.Foreground = 'DarkRed'
        }
    } else {
        $txtStatus.Text = "ℹ️ Deallocation canceled by user."
        $txtStatus.Foreground = 'Gray'
    }
})

$btnRefresh.Add_Click({
    Update-StatusDisplay
})

# Show GUI
$window.ShowDialog() | Out-Null 
