# Setup script for reorient_scan_volume task.
# Launches Blue Sky Plan with the misaligned_sample.bsp project file pre-loaded.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_reorient_scan_volume.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up reorient_scan_volume task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # ---- Close any open Blue Sky Plan instances ----
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*nats-server*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Start-Sleep -Seconds 2

    # Delete crash log so BSP doesn't show crash dialog
    Remove-Item "C:\Users\Docker\AppData\Local\BlueSkyBio\Blue Sky Plan\crashinfo.log" -Force -ErrorAction SilentlyContinue

    # ---- Ensure output directory exists ----
    $outputDir = "C:\Users\Docker\Documents\ReorientedScan"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    # ---- Verify project file exists ----
    $projectFile = "C:\workspace\data\misaligned_sample.bsp"
    if (Test-Path $projectFile) {
        Write-Host "Project file found: $projectFile"
    } else {
        Write-Host "WARNING: Project file not found at $projectFile"
    }

    # ---- Ensure Mesa OpenGL is set up (required for software rendering in QEMU) ----
    try { Setup-MesaOpenGL } catch { Write-Host "WARNING: Setup-MesaOpenGL: $($_.Exception.Message)" }

    # ---- Launch Blue Sky Plan with the project file ----
    $bspExe = Find-BlueSkyPlanExe
    Write-Host "Blue Sky Plan executable: $bspExe"
    Write-Host "Launching Blue Sky Plan with $projectFile..."
    Launch-BlueSkyPlanWithFile -BSPExe $bspExe -FilePath $projectFile -WaitSeconds 30

    # ---- Dismiss any startup dialogs ----
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        & $dismissScript
    }

    # ---- Additional dialog cleanup: wait and retry ----
    Start-Sleep -Seconds 5
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $lateEdge = Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue
    if ($null -ne $lateEdge -and @($lateEdge).Count -gt 0) {
        Write-Host "Late Edge detected, cleaning up..."
        $lateEdge | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        PyAutoGUI-Click -X 814 -Y 255
        Start-Sleep -Seconds 1
        Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        PyAutoGUI-Click -X 322 -Y 104
        Start-Sleep -Seconds 1
    }
    $ErrorActionPreference = $prevEAP

    # ---- Verify Blue Sky Plan is running ----
    $bspProc = Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*Launcher*"
    } | Select-Object -First 1
    if ($bspProc) {
        Write-Host "Blue Sky Plan is running (PID: $($bspProc.Id))"
    } else {
        Write-Host "WARNING: Blue Sky Plan process not found after launch."
    }

    Write-Host "=== reorient_scan_volume task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
