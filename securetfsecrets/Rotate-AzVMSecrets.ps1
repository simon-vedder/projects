<#
.SYNOPSIS
    Automated Azure VM credential rotation runbook for Windows and Linux VMs.

.DESCRIPTION
    Rotates admin passwords and SSH keys for Azure VMs based on Key Vault expiration dates.
    Runs daily via Azure Automation Schedule with Managed Identity.

.PARAMETER KeyVaultName
    Name of the Azure Key Vault for storing credentials.

.PARAMETER RotationThresholdDays
    Trigger rotation when expiration date is within this many days (default: 7).

.PARAMETER RetentionPolicyDays
    Set new secret expiration to this many days from now (default: 90).

.PARAMETER SubscriptionScope
    "All" to process all accessible subscriptions, or comma-separated subscription IDs.

.PARAMETER DryRun
    Simulate operations without making changes (default: false).

.NOTES
    File Name      : Rotate-AzVMSecrets.ps1
    Author         : Simon Vedder
    Date           : 01.11.2025

    Version: 1.0.0
    Required Modules: Az.Accounts, Az.Compute, Az.KeyVault, Az.Resources
    Required Roles:
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [int]$RotationThresholdDays = 7,

    [Parameter(Mandatory = $false)]
    [int]$RetentionPolicyDays = 90,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionScope = "All",

    [Parameter(Mandatory = $false)]
    [bool]$DryRun = $false
)

#Requires -Modules Az.Accounts, Az.Compute, Az.KeyVault, Az.Resources

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "$timestamp [$Level] $Message" 
}

function New-StrongPassword {
    param([int]$Length = 24)
    
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?"
    $bytes = New-Object byte[] $Length
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    
    $password = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    
    # Ensure complexity
    if ($password -notmatch '[a-z]') { $password = $password.Insert(0, 'a') }
    if ($password -notmatch '[A-Z]') { $password = $password.Insert(1, 'A') }
    if ($password -notmatch '[0-9]') { $password = $password.Insert(2, '1') }
    if ($password -notmatch '[^a-zA-Z0-9]') { $password = $password.Insert(3, '!') }
    
    return $password
}

function New-SSHKeyPair {
    param([string]$KeyName)

    # RSA Key erstellen
    $rsa = [System.Security.Cryptography.RSA]::Create(4096)
    
    # Private Key exportieren (PEM/PKCS#8)
    $privateKeyBytes = $rsa.ExportPkcs8PrivateKey()
    $privateKeyBase64 = [Convert]::ToBase64String($privateKeyBytes, [System.Base64FormattingOptions]::InsertLineBreaks)
    $privateKey = "-----BEGIN PRIVATE KEY-----`n$privateKeyBase64`n-----END PRIVATE KEY-----`n"
    
    # Public Key im SSH Format
    # Wir müssen den RSA Public Key manuell in SSH Format konvertieren
    $rsaParams = $rsa.ExportParameters($false)
    
    # SSH-RSA Format: type + exponent + modulus
    $typeBytes = [System.Text.Encoding]::ASCII.GetBytes("ssh-rsa")
    $typeLength = [BitConverter]::GetBytes($typeBytes.Length)
    [Array]::Reverse($typeLength)
    
    $exponentLength = [BitConverter]::GetBytes($rsaParams.Exponent.Length)
    [Array]::Reverse($exponentLength)
    
    $modulusLength = [BitConverter]::GetBytes($rsaParams.Modulus.Length + 1)
    [Array]::Reverse($modulusLength)
    
    # SSH Public Key zusammenbauen
    $buffer = @()
    $buffer += $typeLength
    $buffer += $typeBytes
    $buffer += $exponentLength
    $buffer += $rsaParams.Exponent
    $buffer += $modulusLength
    $buffer += 0x00  # Padding byte
    $buffer += $rsaParams.Modulus
    
    $publicKeyBase64 = [Convert]::ToBase64String($buffer)
    $publicKey = "ssh-rsa $publicKeyBase64"
    
    $rsa.Dispose()
    
    return @{ PrivateKey = $privateKey; PublicKey = $publicKey }
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

$startTime = Get-Date
Write-Log "====== VM Credential Rotation Started ======" -Level Info
Write-Log "KeyVault: $KeyVaultName | Threshold: $RotationThresholdDays days | Retention: $RetentionPolicyDays days" -Level Info

# Authenticate with Managed Identity
try {
    Write-Log "Connecting with Managed Identity..." -Level Info
    $null = Connect-AzAccount -Identity -ErrorAction Stop
    Write-Log "Authentication successful" -Level Success
}
catch {
    Write-Log "Authentication failed: $_" -Level Error
    exit 1
}

# Get subscriptions
try {
    if ($SubscriptionScope -eq "All") {
        $subscriptions = Get-AzSubscription
    }
    else {
        $subscriptions = ($SubscriptionScope -split ",") | ForEach-Object { Get-AzSubscription -SubscriptionId $_.Trim() }
    }
    Write-Log "Found $($subscriptions.Count) subscription(s)" -Level Success
}
catch {
    Write-Log "Failed to get subscriptions: $_" -Level Error
    exit 1
}

# Statistics
$stats = @{
    TotalVMs = 0
    Rotated = 0
    Failed = 0
    Skipped = 0
}

# Process each subscription
foreach ($sub in $subscriptions) {
    Write-Log "Processing subscription: $($sub.Name)" -Level Info
    $null = Set-AzContext -SubscriptionId $sub.Id
    
    $vms = Get-AzVM
    $stats.TotalVMs += $vms.Count
    Write-Log "Found $($vms.Count) VMs" -Level Info
    
    foreach ($vm in $vms) {
        try {
            Write-Log "----------------------------------------" -Level Info
            Write-Log "VM: $($vm.Name) | OS: $($vm.StorageProfile.OsDisk.OsType)" -Level Info
            
            $adminUsername = $vm.OSProfile.AdminUsername
            $osType = $vm.StorageProfile.OsDisk.OsType
            $needsRotation = $false
            
            # ========== WINDOWS VM ==========
            if ($osType -eq "Windows") {
                $secretName = "$($vm.Name)-$adminUsername-pw"
                
                # Check if rotation needed
                try {
                    $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -ErrorAction Stop
                    
                    if ($null -eq $secret.Attributes.Expires) {
                        Write-Log "No expiration date, needs rotation" -Level Warning
                        $needsRotation = $true
                    }
                    else {
                        $daysUntilExpiration = ($secret.Attributes.Expires - (Get-Date)).Days
                        Write-Log "Expires in $daysUntilExpiration days" -Level Info
                        
                        if ($daysUntilExpiration -le $RotationThresholdDays) {
                            $needsRotation = $true
                        }
                    }
                }
                catch {
                    Write-Log "Secret not found, needs creation" -Level Warning
                    $needsRotation = $true
                }
                
                # Rotate if needed
                if ($needsRotation) {
                    Write-Log "Rotating Windows password..." -Level Info
                    
                    # Check VM power state
                    $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
                    $powerState = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" } | Select-Object -ExpandProperty Code
                    $isRunning = $powerState -eq "PowerState/running"
                    
                    if (-not $isRunning) {
                        Write-Log "VM is not running (State: $powerState), skipping rotation" -Level Warning
                        $stats.Skipped++
                        continue
                    }
                    
                    if ($DryRun) {
                        Write-Log "[DRY-RUN] Would rotate password" -Level Warning
                        $stats.Skipped++
                        continue
                    }
                    
                    # Generate new password
                    $newPassword = New-StrongPassword
                    $securePassword = ConvertTo-SecureString -String $newPassword -AsPlainText -Force
                    
                    # Update VM via extension FIRST (before storing in Key Vault)
                    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
                    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                    
                    try {
                        # Install extension
                        $null = Set-AzVMExtension `
                            -ResourceGroupName $vm.ResourceGroupName `
                            -VMName $vm.Name `
                            -Name "VMAccessAgent" `
                            -Publisher "Microsoft.Compute" `
                            -ExtensionType "VMAccessAgent" `
                            -TypeHandlerVersion "2.4" `
                            -Settings @{ UserName = $adminUsername } `
                            -ProtectedSettings @{ Password = $plainPassword } `
                            -ErrorAction Stop `
                            -Location $vm.Location `
                            -ForceRerun (New-Guid).Guid

                        Write-Log "VM password updated successfully" -Level Success
                        
                        # Store in Key Vault ONLY after successful VM update
                        $expirationDate = (Get-Date).AddDays($RetentionPolicyDays)
                        $null = Set-AzKeyVaultSecret `
                            -VaultName $KeyVaultName `
                            -Name $secretName `
                            -SecretValue $securePassword `
                            -Expires $expirationDate `
                            -Tag @{ 
                                VMName = $vm.Name
                                AdminName = $adminUsername
                                OSType = "Windows"
                                LastRotated = (Get-Date -Format "yyyy-MM-dd")
                            }
                        Write-Log "Password stored in Key Vault" -Level Success
                        $stats.Rotated++
                    }
                    catch {
                        Write-Log "Failed to update VM password: $_" -Level Error
                        $stats.Failed++
                    }
                    finally {
                        # Clear memory
                        $newPassword = $null
                        $plainPassword = $null
                        $securePassword = $null
                        [System.GC]::Collect()
                    }
                }
                else {
                    Write-Log "No rotation needed" -Level Info
                    $stats.Skipped++
                }
            }
            
            # ========== LINUX VM ==========
            elseif ($osType -eq "Linux") {
                $passwordSecretName = "$($vm.Name)-$adminUsername-pw"
                $sshSecretName = "$($vm.Name)-$adminUsername-ssh-priv"
                $sshSecretPubName = "$($vm.Name)-$adminUsername-ssh-pub"
                $passwordAuthEnabled = -not $vm.OSProfile.LinuxConfiguration.DisablePasswordAuthentication
                
                # Rotate password if enabled
                if ($passwordAuthEnabled) {
                    Write-Log "Password authentication enabled" -Level Info
                    
                    try {
                        $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $passwordSecretName -ErrorAction Stop
                        
                        if ($null -eq $secret.Attributes.Expires) {
                            $needsRotation = $true
                        }
                        else {
                            $daysUntilExpiration = ($secret.Attributes.Expires - (Get-Date)).Days
                            Write-Log "Password expires in $daysUntilExpiration days" -Level Info
                            $needsRotation = ($daysUntilExpiration -le $RotationThresholdDays)
                        }
                    }
                    catch {
                        $needsRotation = $true
                    }
                    
                    if ($needsRotation) {
                        Write-Log "Rotating Linux password..." -Level Info
                        
                        # Check VM power state
                        $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
                        $powerState = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" } | Select-Object -ExpandProperty Code
                        $isRunning = $powerState -eq "PowerState/running"
                        
                        if (-not $isRunning) {
                            Write-Log "VM is not running (State: $powerState), skipping rotation" -Level Warning
                            $stats.Skipped++
                            continue
                        }
                        
                        if ($DryRun) {
                            Write-Log "[DRY-RUN] Would rotate password" -Level Warning
                        }
                        else {
                            $newPassword = New-StrongPassword
                            $securePassword = ConvertTo-SecureString -String $newPassword -AsPlainText -Force
                            
                            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
                            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                            
                            try {
                                
                                $protectedSettings = @{
                                    username = $adminUsername
                                    password = $plainPassword
                                    reset_ssh = $false
                                }

                                $null = Set-AzVMExtension `
                                    -ResourceGroupName $vm.ResourceGroupName `
                                    -VMName $vm.Name `
                                    -Name "VMAccessForLinux" `
                                    -Publisher "Microsoft.OSTCExtensions" `
                                    -ExtensionType "VMAccessForLinux" `
                                    -TypeHandlerVersion "1.5" `
                                    -ProtectedSettings $protectedSettings `
                                    -ErrorAction Stop `
                                    -Location $vm.Location `
                                    -ForceRerun (New-Guid).Guid
                                
                                Write-Log "Linux password updated" -Level Success
                                
                                # Store in Key Vault AFTER successful VM update
                                $expirationDate = (Get-Date).AddDays($RetentionPolicyDays)
                                $null = Set-AzKeyVaultSecret `
                                    -VaultName $KeyVaultName `
                                    -Name $passwordSecretName `
                                    -SecretValue $securePassword `
                                    -Expires $expirationDate `
                                    -Tag @{ VMName = $vm.Name; AdminName = $adminUsername; OSType = "Linux"; Type = "Password"; LastRotated = (Get-Date -Format "yyyy-MM-dd")}
                                
                                $stats.Rotated++
                            }
                            catch {
                                Write-Log "Failed to update Linux password: $_" -Level Error
                                $stats.Failed++
                            }
                            finally {
                                $newPassword = $null
                                $plainPassword = $null
                                $securePassword = $null
                                [System.GC]::Collect()
                            }
                        }
                    }
                    else {
                        Write-Log "No rotation needed" -Level Info
                        $stats.Skipped++
                    }
                }
                
                # Rotate SSH key
                Write-Log "Checking SSH key..." -Level Info
                $needsSSHRotation = $false
                
                try {
                    $sshSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $sshSecretName -ErrorAction Stop
                    
                    if ($null -eq $sshSecret.Attributes.Expires) {
                        $needsSSHRotation = $true
                    }
                    else {
                        $daysUntilExpiration = ($sshSecret.Attributes.Expires - (Get-Date)).Days
                        Write-Log "SSH key expires in $daysUntilExpiration days" -Level Info
                        $needsSSHRotation = ($daysUntilExpiration -le $RotationThresholdDays)
                    }
                }
                catch {
                    $needsSSHRotation = $true
                }
                
                if ($needsSSHRotation) {
                    Write-Log "Rotating SSH key..." -Level Info
                    
                    # Check VM power state
                    $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
                    $powerState = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" } | Select-Object -ExpandProperty Code
                    $isRunning = $powerState -eq "PowerState/running"
                    
                    if (-not $isRunning) {
                        Write-Log "VM is not running (State: $powerState), skipping SSH rotation" -Level Warning
                        $stats.Skipped++
                        continue
                    }
                    
                    if ($DryRun) {
                        Write-Log "[DRY-RUN] Would rotate SSH key" -Level Warning
                        $stats.Skipped++
                    }
                    else {
                        $keyPair = New-SSHKeyPair -KeyName "$($vm.Name)-$adminUsername"
                        $securePrivateKey = ConvertTo-SecureString -String $keyPair.PrivateKey -AsPlainText -Force
                        $securePublicKey = ConvertTo-SecureString -String $keyPair.PublicKey -AsPlainText -Force
                        
                        try {
                            $protectedSettings = @{
                                username = $adminUsername
                                ssh_key = $keyPair.PublicKey
                                reset_ssh = $true               #can be set to false if you want to keep ssh data
                                remove_prior_keys = $true       #can be set to false if you want to keep existing keys
                            }

                            $null = Set-AzVMExtension `
                                -ResourceGroupName $vm.ResourceGroupName `
                                -VMName $vm.Name `
                                -Name "VMAccessForLinux" `
                                -Publisher "Microsoft.OSTCExtensions" `
                                -ExtensionType "VMAccessForLinux" `
                                -TypeHandlerVersion "1.5" `
                                -ProtectedSettings $protectedSettings `
                                -ErrorAction Stop `
                                -Location $vm.Location `
                                -ForceRerun (New-Guid).Guid
                            
                            Write-Log "SSH key updated" -Level Success
                            
                            # Store in Key Vault AFTER successful VM update
                            $expirationDate = (Get-Date).AddDays($RetentionPolicyDays)
                            $null = Set-AzKeyVaultSecret `
                                -VaultName $KeyVaultName `
                                -Name $sshSecretName `
                                -SecretValue $securePrivateKey `
                                -Expires $expirationDate `
                                -Tag @{ VMName = $vm.Name; AdminName = $adminUsername; OSType = "Linux"; Type = "SSHKey"; LastRotated = (Get-Date -Format "yyyy-MM-dd") }

                            $null = Set-AzKeyVaultSecret `
                                -VaultName $KeyVaultName `
                                -Name $sshSecretPubName `
                                -SecretValue $securePublicKey `
                                -Expires $expirationDate `
                                -Tag @{ VMName = $vm.Name; AdminName = $adminUsername; OSType = "Linux"; Type = "SSHPublicKey"; LastRotated = (Get-Date -Format "yyyy-MM-dd") }
                            
                            $stats.Rotated++
                        }
                        catch {
                            Write-Log "Failed to update SSH key: $_" -Level Error
                            $stats.Failed++
                        }
                        finally {
                            $keyPair = $null
                            $securePrivateKey = $null
                            [System.GC]::Collect()
                        }
                    }
                }
                else {
                    Write-Log "SSH key does not need rotation" -Level Info
                    $stats.Skipped++
                }
            }
        }
        catch {
            Write-Log "Error processing VM $($vm.Name): $_" -Level Error
            $stats.Failed++
        }
    }
}

# Summary
$duration = (Get-Date) - $startTime
Write-Log "----------------------------------------" -Level Info
Write-Log "=============== Summary ===============" -Level Info
Write-Log "Duration: $($duration.ToString('mm\:ss'))" -Level Info
Write-Log "Total VMs: $($stats.TotalVMs)" -Level Info
Write-Log "Rotated: $($stats.Rotated)" -Level Success
Write-Log "Skipped: $($stats.Skipped)" -Level Info
Write-Log "Failed: $($stats.Failed)" -Level $(if ($stats.Failed -gt 0) { 'Error' } else { 'Info' })

if ($DryRun) {
    Write-Log "DRY-RUN MODE - No changes made" -Level Warning
}

Write-Log "Completed" -Level Success
exit $(if ($stats.Failed -gt 0) { 1 } else { 0 })