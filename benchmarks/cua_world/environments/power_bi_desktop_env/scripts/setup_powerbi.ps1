Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup script for Power BI Desktop environment.
# This script runs after Windows boots (post_start hook).

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Power BI Desktop environment ==="

    # Create working directory on Desktop
    $TasksDir = "C:\Users\Docker\Desktop\PowerBITasks"
    New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

    # Copy data files from workspace to Desktop for easy access
    if (Test-Path "C:\workspace\data") {
        Copy-Item "C:\workspace\data\*" -Destination $TasksDir -Force -ErrorAction SilentlyContinue
        Write-Host "Data files copied to: $TasksDir"
    }

    # Disable Power BI auto-update checks
    $pbiRegPath = "HKCU:\Software\Microsoft\Microsoft Power BI Desktop"
    if (-not (Test-Path $pbiRegPath)) {
        New-Item -Path $pbiRegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $pbiRegPath -Name "DisableUpdateNotification" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    # Disable Power BI telemetry/customer experience program
    $pbiCxpPath = "HKCU:\Software\Microsoft\Microsoft Power BI Desktop\CXP"
    if (-not (Test-Path $pbiCxpPath)) {
        New-Item -Path $pbiCxpPath -Force | Out-Null
    }
    Set-ItemProperty -Path $pbiCxpPath -Name "Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Host "Registry settings configured."

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
    # Uninstall OneDrive silently (non-blocking to avoid hanging the hook)
    $oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    if (-not (Test-Path $oneDriveSetup)) {
        $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe"
    }
    if (Test-Path $oneDriveSetup) {
        $proc = Start-Process $oneDriveSetup -ArgumentList "/uninstall" -PassThru -ErrorAction SilentlyContinue
        if ($proc) {
            $finished = $proc.WaitForExit(30000)  # 30 second timeout
            if ($finished) {
                Write-Host "OneDrive uninstalled."
            } else {
                Write-Host "OneDrive uninstall still running (continuing)."
            }
        }
    }
    # Disable Windows Backup notifications
    $backupPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $backupPath)) {
        New-Item -Path $backupPath -Force | Out-Null
    }
    Set-ItemProperty -Path $backupPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force

    # Kill Azure Data Studio if it auto-started (wrong app should not be open)
    Write-Host "Killing Azure Data Studio if present..."
    Get-Process "azuredatastudio", "AzureDataStudio" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # Remove Azure Data Studio from auto-start registry
    $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $runKey -Name "AzureDataStudio" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $runKey -Name "Azure Data Studio" -ErrorAction SilentlyContinue

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) { . $utils; Write-Host "Loaded task_utils.ps1" }

    # Warm up Power BI Desktop: launch and close to complete first-run cycle.
    Write-Host "Warming up Power BI Desktop (first-run cycle)..."
    $pbiExe = $null
    # Try the helper function first, then fallback to hardcoded paths
    try { $pbiExe = Find-PowerBIExe } catch { }
    if (-not $pbiExe) {
        $pbiPaths = @(
            "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe",
            "C:\Program Files (x86)\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
        )
        foreach ($p in $pbiPaths) {
            if (Test-Path $p) {
                $pbiExe = $p
                break
            }
        }
    }
    if (-not $pbiExe) {
        # Broader recursive search
        $found = Get-ChildItem "C:\Program Files" -Recurse -Filter "PBIDesktop.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { $found = Get-ChildItem "C:\Program Files (x86)" -Recurse -Filter "PBIDesktop.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if ($found) { $pbiExe = $found.FullName }
    }
    if ($pbiExe) { Write-Host "Power BI Desktop found at: $pbiExe" }

    if ($pbiExe) {
        $warmupScript = "C:\Windows\Temp\warmup_powerbi.cmd"
        $warmupContent = "@echo off`r`nstart `"`" `"$pbiExe`""
        [System.IO.File]::WriteAllText($warmupScript, $warmupContent)

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN "WarmupPowerBI" /TR "cmd /c $warmupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN "WarmupPowerBI" 2>$null
        Start-Sleep -Seconds 20
        # Kill Power BI and its sub-processes
        Get-Process PBIDesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Get-Process msmdsrv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        schtasks /Delete /TN "WarmupPowerBI" /F 2>$null
        Remove-Item $warmupScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
        Write-Host "Power BI Desktop warm-up complete."
    } else {
        Write-Host "WARNING: Power BI Desktop executable not found for warm-up."
    }

    # Kill Azure Data Studio again in case it re-appeared during warm-up
    Get-Process "azuredatastudio", "AzureDataStudio" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Clean up desktop in Session 1 (minimize terminals, close Start menu)
    $cleanupScript = "C:\Windows\Temp\cleanup_desktop.ps1"
    @'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
(New-Object -ComObject Shell.Application).MinimizeAll()
'@ | Set-Content $cleanupScript -Encoding UTF8
    $prevEAP2 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN "CleanupDesktop_GA" /TR "powershell -ExecutionPolicy Bypass -File $cleanupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "CleanupDesktop_GA" 2>$null
    Start-Sleep -Seconds 5
    schtasks /Delete /TN "CleanupDesktop_GA" /F 2>$null
    Remove-Item $cleanupScript -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP2

    # List available data files
    Write-Host "Available data files in $TasksDir :"
    Get-ChildItem $TasksDir | ForEach-Object { Write-Host "  - $($_.Name)" }

    Write-Host "=== Power BI Desktop environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
