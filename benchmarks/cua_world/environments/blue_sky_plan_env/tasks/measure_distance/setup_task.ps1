# Setup script for measure_distance task.
# Opens Blue Sky Plan with DICOM data loaded.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_measure_distance.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up measure_distance task ==="

    # Load shared helpers
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
    # Delete crash log so BSP doesn't show crash dialog
    Remove-Item "C:\Users\Docker\AppData\Local\BlueSkyBio\Blue Sky Plan\crashinfo.log" -Force -ErrorAction SilentlyContinue

    # Ensure output directory and clean previous output
    $taskDir = "C:\Users\Docker\Desktop\BlueSkyPlanTasks"
    New-Item -ItemType Directory -Force -Path $taskDir | Out-Null
    $outputFile = "$taskDir\measurement.bsp"
    if (Test-Path $outputFile) {
        Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
    }

    # Record task start timestamp
    $taskStartTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $taskStartTime | Out-File -FilePath "$taskDir\task_start.txt" -Force

    # Ensure Mesa OpenGL is set up (may be missing from BlueSkyPlan4)
    try { Setup-MesaOpenGL } catch { Write-Host "WARNING: Setup-MesaOpenGL: $($_.Exception.Message)" }

    # Find and launch Blue Sky Plan
    $bspExe = Find-BlueSkyPlanExe
    Write-Host "Blue Sky Plan executable: $bspExe"
    Write-Host "Launching Blue Sky Plan..."
    Launch-BlueSkyPlanInteractive -BSPExe $bspExe -WaitSeconds 25

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs (pass 1)..."
        & $dismissScript
    }

    # ---- Additional dialog cleanup: BSP login flow can be delayed ----
    # Wait and do a second pass to catch late-appearing login popups
    Start-Sleep -Seconds 5
    $prevEAP2 = $ErrorActionPreference
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
    # Final escape for any remaining overlay
    PyAutoGUI-Press -Key "escape"
    Start-Sleep -Seconds 1
    $ErrorActionPreference = $prevEAP2

    # Run dismiss_dialogs a second time in case login flow restarted
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs (pass 2)..."
        & $dismissScript
    }

    # Verify process running
    $bspProc = Get-Process | Where-Object { $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*Launcher*" } | Select-Object -First 1
    if ($bspProc) {
        Write-Host "Blue Sky Plan is running (PID: $($bspProc.Id))"
    } else {
        Write-Host "WARNING: Blue Sky Plan process not found."
    }

    Write-Host "=== measure_distance task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
