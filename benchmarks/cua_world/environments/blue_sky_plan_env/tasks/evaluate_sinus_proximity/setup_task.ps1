# Setup script for evaluate_sinus_proximity task.
# Launches Blue Sky Plan fresh, sets up Mesa OpenGL, dismisses dialogs,
# and verifies DICOM data exists for the agent to import.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_evaluate_sinus_proximity.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up evaluate_sinus_proximity task ==="

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
    $outputDir = "C:\Users\Docker\Documents"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    # ---- Verify DICOM data exists ----
    $dicomDir = "C:\Users\Docker\Documents\DentalDICOM"
    if (Test-Path $dicomDir) {
        $dicomFiles = @(Get-ChildItem -Path $dicomDir -File -ErrorAction SilentlyContinue)
        Write-Host "DICOM directory found: $dicomDir ($($dicomFiles.Count) files)"
    } else {
        Write-Host "WARNING: DICOM directory not found at $dicomDir"
        # Also check workspace data path
        $altDicom = "C:\workspace\data\dicom"
        if (Test-Path $altDicom) {
            Write-Host "Found DICOM at alternate path: $altDicom"
        }
    }

    # ---- Ensure Mesa OpenGL is set up (required for software rendering in QEMU) ----
    try { Setup-MesaOpenGL } catch { Write-Host "WARNING: Setup-MesaOpenGL: $($_.Exception.Message)" }

    # ---- Find and launch Blue Sky Plan ----
    $bspExe = Find-BlueSkyPlanExe
    Write-Host "Blue Sky Plan executable: $bspExe"
    Write-Host "Launching Blue Sky Plan..."
    Launch-BlueSkyPlanInteractive -BSPExe $bspExe -WaitSeconds 25

    # ---- Dismiss any startup dialogs ----
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        & $dismissScript
    }

    # ---- Additional dialog cleanup: wait and retry ----
    # BSP login flow can be delayed; do a second pass
    Start-Sleep -Seconds 5
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $lateEdge = Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue
    if ($null -ne $lateEdge -and @($lateEdge).Count -gt 0) {
        Write-Host "Late Edge detected after dismiss_dialogs, cleaning up..."
        $lateEdge | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        # Close login popup
        PyAutoGUI-Click -X 814 -Y 255
        Start-Sleep -Seconds 1
        Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        # Back button in case click hit hex grid
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

    Write-Host "=== evaluate_sinus_proximity task setup complete ==="
    Write-Host "Agent should import DICOM data from C:\Users\Docker\Documents\DentalDICOM"
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
