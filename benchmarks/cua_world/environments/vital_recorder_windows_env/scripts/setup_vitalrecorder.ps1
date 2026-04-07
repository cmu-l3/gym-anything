# setup_vitalrecorder.ps1 - Post-start hook: configure Vital Recorder and warm-up launch
# This runs after the VM boots and software is installed.
# It performs a warm-up launch to clear first-run dialogs, then kills the app.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Vital Recorder ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Step 1: Disable OneDrive (common Windows cleanup)
    Write-Host "Step 1: Disabling OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue 2>$null
        $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe"
        if (Test-Path $oneDriveSetup) {
            $proc = Start-Process $oneDriveSetup -ArgumentList "/uninstall" -PassThru
            $finished = $proc.WaitForExit(30000)
            if (-not $finished) {
                $proc.Kill()
            }
        }
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    Write-Host "OneDrive disabled."

    # Step 2: Disable Windows consumer features and telemetry
    Write-Host "Step 2: Disabling Windows consumer features..."
    $cloudPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $cloudPath)) {
        New-Item -Path $cloudPath -Force | Out-Null
    }
    Set-ItemProperty -Path $cloudPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force

    # Step 3: Ensure vital data files are on Desktop
    Write-Host "Step 3: Ensuring vital data files are available..."
    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    }

    $sourceData = "C:\workspace\data"
    if (Test-Path $sourceData) {
        Copy-Item "$sourceData\*.vital" -Destination $dataDir -Force -ErrorAction SilentlyContinue
        $fileCount = (Get-ChildItem $dataDir -Filter "*.vital" -ErrorAction SilentlyContinue).Count
        Write-Host "Data directory has $fileCount .vital files"
    }

    # Step 4: Warm-up launch to clear first-run dialogs
    Write-Host "Step 4: Warm-up launch of Vital Recorder..."
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder executable: $vrExe"

    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -WaitSeconds 15

    # Dismiss any first-run dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Running dialog dismissal..."
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogsWarmup_GA" -WaitSeconds 15
    }

    # Kill Vital Recorder after warm-up (process name is "Vital", not "VitalRecorder")
    Write-Host "Killing Vital Recorder after warm-up..."
    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Step 5: Clean up desktop in Session 1 (minimize terminals, close Start menu)
    Write-Host "Step 5: Cleaning up desktop..."
    $cleanupScript = "C:\Windows\Temp\cleanup_desktop.ps1"
    @'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
(New-Object -ComObject Shell.Application).MinimizeAll()
'@ | Set-Content $cleanupScript -Encoding UTF8
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN "CleanupDesktop_GA" /TR "powershell -ExecutionPolicy Bypass -File $cleanupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "CleanupDesktop_GA" 2>$null
    Start-Sleep -Seconds 5
    schtasks /Delete /TN "CleanupDesktop_GA" /F 2>$null
    Remove-Item $cleanupScript -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP

    Write-Host "=== Vital Recorder setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
