Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Post-start setup for Blue Sky Plan environment.
# Performs warm-up launch to dismiss first-run dialogs, then force-kills BSP.
# Pattern: same as NinjaTrader, Power BI, Excel — force-kill after warm-up.
# The pre_task hook handles crash dialogs on each launch.

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Blue Sky Plan environment ==="

    # Load shared utilities
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) {
        . $utils
    } else {
        Write-Host "WARNING: task_utils.ps1 not found at $utils"
    }

    # Disable Windows Update and kill OneDrive to reduce interference
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Write-Host "Disabling Windows Update..."
    Stop-Service wuauserv -Force 2>$null
    Set-Service wuauserv -StartupType Disabled 2>$null
    Write-Host "Killing OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process "OneDrive.Sync.Service" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP

    # Ensure Mesa OpenGL is set up (installer may not have finished BlueSkyPlan4 during pre_start)
    try {
        Setup-MesaOpenGL
    } catch {
        Write-Host "WARNING: Setup-MesaOpenGL failed: $($_.Exception.Message)"
    }

    # Create Desktop directories for tasks
    $taskDir = "C:\Users\Docker\Desktop\BlueSkyPlanTasks"
    New-Item -ItemType Directory -Force -Path $taskDir | Out-Null

    # Check DICOM data availability
    $dicomSource = "C:\Users\Docker\Documents\DentalDICOM"
    if (Test-Path $dicomSource) {
        $fileCount = (Get-ChildItem $dicomSource -Recurse -File).Count
        Write-Host "DICOM data available at: $dicomSource ($fileCount files)"
    } else {
        Write-Host "WARNING: DICOM data not found at $dicomSource"
    }

    # Find Blue Sky Plan launcher
    try {
        $bspExe = Find-BlueSkyPlanExe
        Write-Host "Blue Sky Plan launcher: $bspExe"
    } catch {
        Write-Host "WARNING: Blue Sky Plan not found. Warm-up launch skipped."
        Write-Host "BSP may not be installed. Check pre_start log."
        Write-Host "=== Blue Sky Plan setup complete (no BSP found) ==="
        return
    }

    # Warm-up launch: start BSP, dismiss first-run dialogs, then force-kill.
    # Force-kill creates crash markers, but the pre_task dismiss_dialogs.ps1
    # handles the crash dialog on each launch (same pattern as other envs).
    Write-Host "Performing warm-up launch to dismiss first-run dialogs..."
    Launch-BlueSkyPlanInteractive -BSPExe $bspExe -WaitSeconds 30

    # Dismiss any dialogs (hardware warning, crash report, login popup)
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Running dialog dismissal..."
        & $dismissScript
    }

    Start-Sleep -Seconds 3

    # Force-kill BSP (same pattern as NinjaTrader, Power BI, Excel envs)
    Write-Host "Force-killing BSP after warm-up..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or
        $_.ProcessName -like "*Launcher*" -or
        $_.ProcessName -like "*nats-server*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Start-Sleep -Seconds 3

    # Clean up desktop in Session 1 (minimize terminals, close Start menu)
    Write-Host "Cleaning up desktop..."
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

    Write-Host "=== Blue Sky Plan setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
