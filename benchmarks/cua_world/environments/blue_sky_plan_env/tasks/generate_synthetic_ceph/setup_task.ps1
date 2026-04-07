# Setup script for generate_synthetic_ceph task.
# Launches Blue Sky Plan with Mesa OpenGL and dialog dismissal.
# Agent will need to load the CBCT scan data.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_generate_synthetic_ceph.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up generate_synthetic_ceph task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Close any open Blue Sky Plan instances
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*nats-server*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Start-Sleep -Seconds 2

    Remove-Item "C:\Users\Docker\AppData\Local\BlueSkyBio\Blue Sky Plan\crashinfo.log" -Force -ErrorAction SilentlyContinue

    # Ensure output directory
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\BlueSkyPlan" | Out-Null

    # Verify DICOM data exists
    $dicomDir = "C:\Users\Docker\Documents\DentalDICOM"
    if (Test-Path $dicomDir) {
        $dicomFiles = @(Get-ChildItem -Path $dicomDir -File -ErrorAction SilentlyContinue)
        Write-Host "DICOM directory found: $dicomDir ($($dicomFiles.Count) files)"
    } else {
        Write-Host "WARNING: DICOM directory not found at $dicomDir"
    }

    try { Setup-MesaOpenGL } catch { Write-Host "WARNING: Setup-MesaOpenGL: $($_.Exception.Message)" }

    $bspExe = Find-BlueSkyPlanExe
    Write-Host "Launching Blue Sky Plan..."
    Launch-BlueSkyPlanInteractive -BSPExe $bspExe -WaitSeconds 25

    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        & $dismissScript
    }

    # Additional late-Edge cleanup
    Start-Sleep -Seconds 5
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $lateEdge = Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue
    if ($null -ne $lateEdge -and @($lateEdge).Count -gt 0) {
        $lateEdge | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        PyAutoGUI-Click -X 814 -Y 255
        Start-Sleep -Seconds 1
        Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        PyAutoGUI-Click -X 322 -Y 104
        Start-Sleep -Seconds 1
    }
    $ErrorActionPreference = $prevEAP

    $bspProc = Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*Launcher*"
    } | Select-Object -First 1
    if ($bspProc) { Write-Host "Blue Sky Plan is running (PID: $($bspProc.Id))" }
    else { Write-Host "WARNING: Blue Sky Plan process not found." }

    Write-Host "=== generate_synthetic_ceph task setup complete ==="
    Write-Host "Agent should import DICOM data from C:\Users\Docker\Documents\DentalDICOM"
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
