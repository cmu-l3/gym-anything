Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup script for Microsoft Word 2010 environment.
# This script runs after Windows boots (post_start hook).
# Word 2010 is installed via MSI from Office 2010 Professional Plus ISO.
# No login or activation required.

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Word 2010 environment ==="

    # Create working directory on Desktop
    $TasksDir = "C:\Users\Docker\Desktop\WordTasks"
    New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

    # Copy data files from workspace to Desktop for easy access
    if (Test-Path "C:\workspace\data") {
        Get-ChildItem "C:\workspace\data" -Filter "*.docx" | ForEach-Object {
            Copy-Item $_.FullName -Destination $TasksDir -Force
        }
        Write-Host "Data files copied to: $TasksDir"
    }

    # Aggressively disable OneDrive
    Write-Host "Disabling OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # Remove from startup
    $onedrivePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $onedrivePath -Name "OneDrive" -ErrorAction SilentlyContinue
    # Disable via Group Policy
    $onedrivePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $onedrivePolicyPath)) {
        New-Item -Path $onedrivePolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $onedrivePolicyPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    # Uninstall OneDrive silently (non-blocking with timeout)
    $oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    if (-not (Test-Path $oneDriveSetup)) {
        $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe"
    }
    if (Test-Path $oneDriveSetup) {
        $proc = Start-Process $oneDriveSetup -ArgumentList "/uninstall" -PassThru -ErrorAction SilentlyContinue
        if ($proc) {
            $finished = $proc.WaitForExit(30000)
            if ($finished) {
                Write-Host "OneDrive uninstalled."
            } else {
                Write-Host "OneDrive uninstall still running (continuing)."
            }
        }
    }
    # Disable Windows Backup/Consumer notifications
    $backupPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $backupPath)) {
        New-Item -Path $backupPath -Force | Out-Null
    }
    Set-ItemProperty -Path $backupPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force

    # Set Office 14.0 registry keys to suppress first-run dialogs and activation
    Write-Host "Setting Office 14.0 registry keys..."
    $regPaths = @(
        "HKCU:\Software\Microsoft\Office\14.0\Common\General",
        "HKCU:\Software\Microsoft\Office\14.0\FirstRun",
        "HKCU:\Software\Microsoft\Office\14.0\Word\Options",
        "HKCU:\Software\Microsoft\Office\14.0\Registration"
    )
    foreach ($rp in $regPaths) {
        if (-not (Test-Path $rp)) {
            New-Item -Path $rp -Force | Out-Null
        }
    }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\Common\General" -Name "ShownFirstRunOptin" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\FirstRun" -Name "BootedRTM" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\FirstRun" -Name "DisableMovie" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\Word\Options" -Name "DisableBootToOfficeStart" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\Registration" -Name "AcceptAllEulas" -Value 1 -Type DWord -Force

    # Suppress "Help Protect and Improve Microsoft Office" dialog (QMEnable/ShownOptIn)
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\Common" -Name "QMEnable" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\Common\General" -Name "ShownOptIn" -Value 1 -Type DWord -Force

    # Machine-wide policies
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Office\14.0\Common\General"
    if (-not (Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $policyPath -Name "ShownFirstRunOptin" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $policyPath -Name "DisableBootToOfficeStart" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $policyPath -Name "ShownOptIn" -Value 1 -Type DWord -Force

    # Disable Office 2010 automatic updates
    $updatePath = "HKCU:\Software\Microsoft\Office\14.0\Common"
    if (-not (Test-Path $updatePath)) {
        New-Item -Path $updatePath -Force | Out-Null
    }
    Set-ItemProperty -Path $updatePath -Name "UpdatesEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue


<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
