Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup script for Microsoft Excel environment.
# This script runs after Windows boots (post_start hook).

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Excel environment ==="

# Create working directory on Desktop
$TasksDir = "C:\Users\Docker\Desktop\ExcelTasks"
New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

# Copy data files from workspace to Desktop for easy access
if (Test-Path "C:\workspace\data") {
    Copy-Item "C:\workspace\data\*" -Destination $TasksDir -Force -ErrorAction SilentlyContinue
    Write-Host "Data files copied to: $TasksDir"
}

# Disable Excel first-run wizard and license prompts via registry
$officeRegPath = "HKCU:\Software\Microsoft\Office\16.0\Common\General"
if (-not (Test-Path $officeRegPath)) {
    New-Item -Path $officeRegPath -Force | Out-Null
}
Set-ItemProperty -Path $officeRegPath -Name "ShownFirstRunOptin" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $officeRegPath -Name "DisableBootToOfficeStart" -Value 1 -Type DWord -Force

# Mark first run as completed to suppress sign-in dialog
$firstRunPath = "HKCU:\Software\Microsoft\Office\16.0\FirstRun"
if (-not (Test-Path $firstRunPath)) {
    New-Item -Path $firstRunPath -Force | Out-Null
}
Set-ItemProperty -Path $firstRunPath -Name "BootedRTM" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $firstRunPath -Name "DisableMovie" -Value 1 -Type DWord -Force

# Suppress Office sign-in and activation dialogs
$licensingPath = "HKCU:\Software\Microsoft\Office\16.0\Common\Licensing"
if (-not (Test-Path $licensingPath)) {
    New-Item -Path $licensingPath -Force | Out-Null
}
Set-ItemProperty -Path $licensingPath -Name "HideActivationUI" -Value 1 -Type DWord -Force

# Accept all EULAs
$regPath2 = "HKCU:\Software\Microsoft\Office\16.0\Registration"
if (-not (Test-Path $regPath2)) {
    New-Item -Path $regPath2 -Force | Out-Null
}
Set-ItemProperty -Path $regPath2 -Name "AcceptAllEulas" -Value 1 -Type DWord -Force

# Machine-wide policy to suppress first-run
$policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\General"
if (-not (Test-Path $policyPath)) {
    New-Item -Path $policyPath -Force | Out-Null
}
Set-ItemProperty -Path $policyPath -Name "ShownFirstRunOptin" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $policyPath -Name "DisableBootToOfficeStart" -Value 1 -Type DWord -Force

# Disable Office "What's New" and update notifications
$whatsNewPath = "HKCU:\Software\Microsoft\Office\16.0\Common"
Set-ItemProperty -Path $whatsNewPath -Name "LastWhatsNewShownVersion" -Value "99.0" -Type String -Force -ErrorAction SilentlyContinue

# Disable Office feedback and connected experiences
$privacyPath = "HKCU:\Software\Microsoft\Office\16.0\Common\Privacy\SettingsStore\Anonymous"
if (-not (Test-Path $privacyPath)) {
    New-Item -Path $privacyPath -Force | Out-Null
}

$regPath = "HKCU:\Software\Microsoft\Office\16.0\Excel\Options"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# Disable Excel Start Screen (go straight to blank workbook or opened file)
Set-ItemProperty -Path $regPath -Name "DisableBootToOfficeStart" -Value 1 -Type DWord -Force

# Disable Protected View for files from the internet (so our data files open without prompts)
$securityPath = "HKCU:\Software\Microsoft\Office\16.0\Excel\Security\ProtectedView"
if (-not (Test-Path $securityPath)) {
    New-Item -Path $securityPath -Force | Out-Null
}
Set-ItemProperty -Path $securityPath -Name "DisableInternetFilesInPV" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $securityPath -Name "DisableUnsafeLocationsInPV" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $securityPath -Name "DisableAttachementsInPV" -Value 1 -Type DWord -Force

# Disable macro security warnings for trusted locations
$trustPath = "HKCU:\Software\Microsoft\Office\16.0\Excel\Security"
if (-not (Test-Path $trustPath)) {
    New-Item -Path $trustPath -Force | Out-Null
}
Set-ItemProperty -Path $trustPath -Name "VBAWarnings" -Value 1 -Type DWord -Force

# Add Desktop\ExcelTasks as trusted location
$trustedLocPath = "HKCU:\Software\Microsoft\Office\16.0\Excel\Security\Trusted Locations\Location10"
if (-not (Test-Path $trustedLocPath)) {
    New-Item -Path $trustedLocPath -Force | Out-Null
}
Set-ItemProperty -Path $trustedLocPath -Name "Path" -Value "C:\Users\Docker\Desktop\ExcelTasks\" -Type String -Force
Set-ItemProperty -Path $trustedLocPath -Name "AllowSubFolders" -Value 1 -Type DWord -Force

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

# Warm up Excel: launch and close to complete the first-run sign-in cycle.
# After this, subsequent launches show a dismissable trial nag instead of
# the mandatory sign-in dialog.
Write-Host "Warming up Excel (first-run cycle)..."
$excelExe = "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE"
if (Test-Path $excelExe) {
    $warmupScript = "C:\Windows\Temp\warmup_excel.cmd"
    $warmupContent = "@echo off`r`nstart `"`" `"$excelExe`""
    [System.IO.File]::WriteAllText($warmupScript, $warmupContent)

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN "WarmupExcel" /TR "cmd /c $warmupScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "WarmupExcel" 2>$null
    Start-Sleep -Seconds 15
    # Kill Excel to complete the cycle
    Get-Process EXCEL -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    schtasks /Delete /TN "WarmupExcel" /F 2>$null
    Remove-Item $warmupScript -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Write-Host "Excel warm-up complete."
}

# Minimize any open terminal/command windows
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
"@
# Try to minimize console windows
Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
    [Win32]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
}

# List available data files
Write-Host "Available data files in $TasksDir :"
Get-ChildItem $TasksDir | ForEach-Object { Write-Host "  - $($_.Name)" }

    Write-Host "=== Excel environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
