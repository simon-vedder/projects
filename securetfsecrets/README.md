# Secure VM Credential Management with Azure Automation

**Problem:** Terraform stores VM passwords in plaintext within the state file, and credentials never expire automatically.

**Solution:** Store initial credentials in Azure Key Vault with expiration dates, then use an Azure Automation runbook to automatically rotate them.

---

## 🎯 What This Solution Does

- ✅ **Automatic daily rotation** of VM admin passwords and SSH keys
- ✅ **Works with running VMs only** - skips stopped VMs to prevent lockouts
- ✅ **Native Key Vault expiration** - uses built-in `expiration_date` property
- ✅ **Multi-subscription support** - process VMs across all subscriptions
- ✅ **Zero secret exposure** - credentials never appear in logs

---

## 🏗️ Architecture
```
Terraform creates VMs
        ↓
Stores initial credentials in Key Vault
        ↓
Azure Automation runs daily
        ↓
Checks expiration dates → Rotates if needed
        ↓
Updates VM via VMAccess extension → Saves new credential to Key Vault
```

---

## 📋 Prerequisites

1. **Azure Automation Account** with Managed Identity
2. **Azure Key Vault** (RBAC enabled)
3. **PowerShell Modules** in Automation Account:
   - `Az.Accounts`, `Az.Compute`, `Az.KeyVault`, `Az.Resources`

---

## 🚀 Quick Setup

### 1. Deploy Infrastructure with Terraform

View main.tf

Your Terraform code creates VMs and stores initial credentials:
```hcl
# Generate random password
resource "random_password" "password" {
  length  = 16
  special = true
}

# Store in Key Vault with expiration
resource "azurerm_key_vault_secret" "password-win" {
  name            = "${local.vm_win_name}-${local.admin_username}-pw"
  key_vault_id    = azurerm_key_vault.this.id
  value           = random_password.password.result
  expiration_date = timeadd(timestamp(), "168h")  # 7 days
  
  tags = {
    VMName      = local.vm_win_name
    AdminName   = local.admin_username
    OSType      = "Windows"
    Type        = "Password"
    LastRotated = formatdate("YYYY-MM-DD", timestamp())
  }
  
  lifecycle {
    ignore_changes = [value, tags, expiration_date]  # Critical!
  }
}

# Use secret in VM
resource "azurerm_windows_virtual_machine" "win" {
  name           = local.vm_win_name
  admin_username = local.admin_username
  admin_password = azurerm_key_vault_secret.password-win.value
  
  # ... other config ...
  
  lifecycle {
    ignore_changes = [admin_password]  # Prevent Terraform drift
  }
}
```

**Key Points:**
- `lifecycle.ignore_changes` prevents Terraform from reverting rotated passwords
- `expiration_date` triggers automatic rotation
- Secrets follow naming pattern: `{VMName}-{AdminUsername}-pw`

### 2. Create Automation Account
### 3. Assign Permissions
- "Virtual Machine Contributor"
- "Key Vault Secrets Officer"

### 4. Upload Runbook
### 5. Create Daily Schedule


---

## ⚙️ Configuration

### Script Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `KeyVaultName` | - | **(Required)** Key Vault name |
| `RotationThresholdDays` | 7 | Rotate when expiration is within X days |
| `RetentionPolicyDays` | 90 | New credentials expire in X days |
| `SubscriptionScope` | "All" | Process all subscriptions or specific IDs |
| `DryRun` | false | Test mode without making changes |

### Secret Naming Convention

- **Windows**: `{VMName}-{AdminUsername}-pw`
- **Linux Password**: `{VMName}-{AdminUsername}-pw`
- **Linux SSH Private**: `{VMName}-{AdminUsername}-ssh-priv`
- **Linux SSH Public**: `{VMName}-{AdminUsername}-ssh-pub`

Example: `demo-vm-win-superman-pw`

---

## 🧪 Testing

### Dry-Run Mode

Test without making changes:
```bash
az automation runbook start \
  --resource-group "rg-automation" \
  --automation-account-name "automation-vm-rotation" \
  --name "Rotate-AzVMSecrets" \
  --parameters '{"KeyVaultName": "your-kv", "DryRun": true}'
```

### Verify Rotation
```powershell
# Check secret expiration
Get-AzKeyVaultSecret -VaultName "your-kv" -Name "demo-vm-win-superman-pw" | 
  Select-Object Name, @{N='Expires';E={$_.Attributes.Expires}}

# Test Windows login
$secret = Get-AzKeyVaultSecret -VaultName "your-kv" -Name "demo-vm-win-superman-pw"
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret.SecretValue)
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
# Use password for RDP
```

---

## 🔧 How It Works

1. **Daily Execution**: Runbook runs at e.g. 02:00 UTC
2. **VM Discovery**: Finds all VMs in target subscriptions
3. **Check Status**: Only processes **running VMs**
4. **Check Expiration**: Reads `expiration_date` from Key Vault
5. **Rotation Logic**:
```
   if (days_until_expiration <= 7):
       generate_new_credential()
       update_vm_via_extension()
       store_in_keyvault()
```
6. **Skip Stopped VMs**: Prevents lockouts

---

## 📊 Example Log Output
```
2025-11-01 02:00:20 [Info] VM: demo-vm-win | OS: Windows
2025-11-01 02:00:21 [Info] Expires in 5 days
2025-11-01 02:00:21 [Info] Rotating Windows password...
2025-11-01 02:00:45 [Success] VM password updated successfully
2025-11-01 02:00:46 [Success] Password stored in Key Vault
2025-11-01 02:00:47 [Info] ----------------------------------------
2025-11-01 02:00:47 [Info] VM: demo-vm-unix | OS: Linux
2025-11-01 02:00:48 [Info] Password expires in 45 days
2025-11-01 02:00:48 [Info] No rotation needed
2025-11-01 02:00:48 [Info] SSH key expires in 3 days
2025-11-01 02:00:48 [Info] Rotating SSH key...
2025-11-01 02:01:12 [Success] SSH key updated
```

---

## 🛡️ Security Benefits

| Approach | Plaintext in State? | Expires? | Auto-Rotation? |
|----------|-------------------|----------|----------------|
| **Bad**: Hardcoded password | ✅ Yes | ❌ Never | ❌ Manual |
| **OK**: Generated + reference in code | ✅ Yes | ❌ Never | ❌ Manual |
| **Good**: Generated + stored secret | ✅ Yes | ❌ Manual | ❌ Manual |
| **Better**: This solution | ❌ No* | ✅ Yes | ✅ Auto |

*Initial password is in state during first `terraform apply`, but rotated within 7 days and never reverted.

---

## 🔄 Complete Terraform Example

See the full Terraform configuration that deploys:
- Windows VM with password auth
- Linux VM with both password and SSH key auth
- Key Vault with RBAC
- Initial secrets with 7-day expiration

[View complete example →](./main.tf/)

---

## 🚨 Troubleshooting

### VM Extension Failed
**Issue**: Extension installation fails  
**Fix**: Verify VM is running and VM Agent is healthy
```powershell
Get-AzVM -ResourceGroupName "rg" -Name "vm-name" -Status
```

### Key Vault Access Denied
**Issue**: Managed Identity can't access secrets  
**Fix**: Verify RBAC role assignment
```bash
az role assignment list --assignee $PRINCIPAL_ID --scope $KEY_VAULT_ID
```

### Stopped VM Skipped
**Issue**: VM not processed  
**Expected**: Script only rotates credentials for running VMs to prevent lockouts

---

## 📝 Best Practices

1. **Test in non-production first** using `DryRun` mode
2. **Set threshold > 7 days** to ensure rotation before expiration
3. **Enable Key Vault audit logs** for compliance
4. **Monitor failed jobs** via Azure Monitor alerts
5. **Keep VM Agent updated** for extension reliability

---

## 📚 Resources

- [Complete PowerShell Script](./Rotate-AzVMSecrets.ps1)
- [Terraform Example](./main.tf)

---

**Author:** Simon Vedder  
**Version:** 1.0.0  
**Date:** 2025-11-01