# generate_audit_events.ps1 - Generate REAL Windows Security events for ADAudit Plus
# These are genuine Windows events created by actual OS operations, NOT synthetic data.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Generating real Windows Security audit events ==="

# -------------------------------------------------------
# 1. Create real local user accounts
#    (Generates Event ID 4720 - User Account Created)
# -------------------------------------------------------
Write-Host "Creating local user accounts..."

$users = @(
    @{Name="jsmith"; FullName="John Smith"; Description="IT Support Technician"},
    @{Name="mjohnson"; FullName="Maria Johnson"; Description="Security Analyst"},
    @{Name="rwilliams"; FullName="Robert Williams"; Description="Network Administrator"},
    @{Name="abrown"; FullName="Alice Brown"; Description="Help Desk Operator"},
    @{Name="dlee"; FullName="David Lee"; Description="System Administrator"}
)

foreach ($user in $users) {
    try {
        $existing = Get-LocalUser -Name $user.Name -ErrorAction SilentlyContinue
        if (-not $existing) {
            $securePass = ConvertTo-SecureString "P@ssw0rd2024!" -AsPlainText -Force
            New-LocalUser -Name $user.Name -Password $securePass -FullName $user.FullName -Description $user.Description -PasswordNeverExpires
            Write-Host "  Created user: $($user.Name) ($($user.FullName))"
        } else {
            Write-Host "  User already exists: $($user.Name)"
        }
    } catch {
        Write-Host "  Failed to create user $($user.Name): $_"
    }
}

# -------------------------------------------------------
# 2. Create local groups and add members
#    (Generates Event IDs 4731, 4732 - Group Created, Member Added)
# -------------------------------------------------------
Write-Host "Creating local groups..."

$groups = @(
    @{Name="IT_Support"; Description="IT Support Team"; Members=@("jsmith", "abrown")},
    @{Name="Security_Team"; Description="Security Operations"; Members=@("mjohnson", "rwilliams")},
    @{Name="Server_Admins"; Description="Server Administrators"; Members=@("rwilliams", "dlee")}
)

foreach ($group in $groups) {
    try {
        $existing = Get-LocalGroup -Name $group.Name -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-LocalGroup -Name $group.Name -Description $group.Description
            Write-Host "  Created group: $($group.Name)"
        }
        foreach ($member in $group.Members) {
            try {
                Add-LocalGroupMember -Group $group.Name -Member $member -ErrorAction SilentlyContinue
                Write-Host "    Added $member to $($group.Name)"
            } catch {
                # Member may already be in group
            }
        }
    } catch {
        Write-Host "  Failed to create group $($group.Name): $_"
    }
}

# -------------------------------------------------------
# 3. Modify user account properties
#    (Generates Event ID 4738 - User Account Changed)
# -------------------------------------------------------
Write-Host "Modifying user accounts..."
try {
    Set-LocalUser -Name "jsmith" -Description "IT Support Technician - Senior" -ErrorAction SilentlyContinue
    Write-Host "  Modified jsmith description"
} catch { Write-Host "  Failed to modify jsmith: $_" }

try {
    Disable-LocalUser -Name "abrown" -ErrorAction SilentlyContinue
    Write-Host "  Disabled abrown account"
    Start-Sleep -Seconds 1
    Enable-LocalUser -Name "abrown" -ErrorAction SilentlyContinue
    Write-Host "  Re-enabled abrown account"
} catch { Write-Host "  Failed to toggle abrown: $_" }

# -------------------------------------------------------
# 4. Generate failed logon events
#    (Generates Event ID 4625 - Failed Logon Attempt)
# -------------------------------------------------------
Write-Host "Generating failed logon events..."

# Use net use to create real failed authentication events
$failTargets = @("baduser1", "baduser2", "wrongadmin", "testattacker", "bruteforce1")
foreach ($target in $failTargets) {
    try {
        net use \\localhost\IPC$ /user:$target "wrongpassword" 2>$null
    } catch { }
    try {
        net use \\localhost\IPC$ /delete 2>$null
    } catch { }
    Start-Sleep -Milliseconds 500
}
Write-Host "  Generated $($failTargets.Count) failed logon events"

# -------------------------------------------------------
# 5. Password change events
#    (Generates Event ID 4724 - Password Reset Attempt)
# -------------------------------------------------------
Write-Host "Generating password change events..."
try {
    $newPass = ConvertTo-SecureString "NewP@ss2024!" -AsPlainText -Force
    Set-LocalUser -Name "dlee" -Password $newPass -ErrorAction SilentlyContinue
    Write-Host "  Reset password for dlee"
} catch { Write-Host "  Failed to reset password: $_" }

# -------------------------------------------------------
# 6. Create a monitored folder for file audit tasks
# -------------------------------------------------------
Write-Host "Creating monitored folders..."
$auditFolder = "C:\AuditTestFolder"
New-Item -ItemType Directory -Force -Path $auditFolder | Out-Null
New-Item -ItemType Directory -Force -Path "$auditFolder\Confidential" | Out-Null
New-Item -ItemType Directory -Force -Path "$auditFolder\Reports" | Out-Null
New-Item -ItemType Directory -Force -Path "$auditFolder\Shared" | Out-Null

# Create some files in the folders
"Quarterly Financial Report Q4 2024" | Out-File "$auditFolder\Confidential\financial_report_q4.txt"
"Employee Performance Reviews 2024" | Out-File "$auditFolder\Confidential\performance_reviews.txt"
"Monthly Audit Summary - December 2024" | Out-File "$auditFolder\Reports\audit_summary_dec.txt"
"Network Infrastructure Diagram" | Out-File "$auditFolder\Shared\network_diagram.txt"
"IT Asset Inventory 2024" | Out-File "$auditFolder\Shared\asset_inventory.csv"

# Set NTFS audit permissions on the folder
$acl = Get-Acl $auditFolder
$auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule(
    "Everyone",
    "ReadAndExecute,Write,Delete",
    "ContainerInherit,ObjectInherit",
    "None",
    "Success,Failure"
)
$acl.AddAuditRule($auditRule)
Set-Acl -Path $auditFolder -AclObject $acl -ErrorAction SilentlyContinue
Write-Host "  Created audit folder: $auditFolder with SACL"

# -------------------------------------------------------
# 7. Generate file access events
# -------------------------------------------------------
Write-Host "Generating file access events..."
Get-Content "$auditFolder\Confidential\financial_report_q4.txt" | Out-Null
"Updated content" | Add-Content "$auditFolder\Shared\asset_inventory.csv"
Write-Host "  Generated file read/write events"

# -------------------------------------------------------
# 8. Service-related events
#    (Generates Event ID 7045 - New Service Installed)
# -------------------------------------------------------
Write-Host "Generating service events..."
try {
    # This generates real Windows Event Log entries for service operations
    $svc = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
        Write-Host "  Toggled Windows Update service (generates service events)"
    }
} catch { Write-Host "  Service event generation: $_" }

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
Write-Host ""
Write-Host "=== Audit event generation complete ==="
Write-Host "  Users created: $($users.Count)"
Write-Host "  Groups created: $($groups.Count)"
Write-Host "  Failed logons: $($failTargets.Count)"
Write-Host "  Audit folder: $auditFolder"
Write-Host ""
Write-Host "These are REAL Windows Security events visible in Event Viewer"
Write-Host "and will be collected by ADAudit Plus for auditing."
