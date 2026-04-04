# Setup script for complete_implant_workflow task.
# Launches Blue Sky Plan fresh so the agent performs the full workflow:
# DICOM import -> panoramic curve -> implant placement -> measurement -> save -> screenshot.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_complete_implant_workflow.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up complete_implant_workflow task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # ---------------------------------------------------------------
    # 1. Kill any existing Blue Sky Plan / NATS processes
    # ---------------------------------------------------------------
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*nats-server*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Start-Sleep -Seconds 2

    # Delete crash log so BSP doesn't show crash-recovery dialog
    Remove-Item "C:\Users\Docker\AppData\Local\BlueSkyBio\Blue Sky Plan\crashinfo.log" -Force -ErrorAction SilentlyContinue

    # ---------------------------------------------------------------
    # 2. Create output directory and clean previous outputs
    # ---------------------------------------------------------------
    $taskDir = "C:\Users\Docker\Desktop\BlueSkyPlanTasks"
    New-Item -ItemType Directory -Force -Path $taskDir | Out-Null

    # Remove previous outputs for this task
    $outputFiles = @(
        "$taskDir\complete_plan.bsp",
        "$taskDir\complete_plan_screenshot.png",
        "$taskDir\complete_workflow_result.json"
    )
    foreach ($f in $outputFiles) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }

    # ---------------------------------------------------------------
    # 3. Record task start timestamp (Unix epoch seconds)
    # ---------------------------------------------------------------
    $taskStartTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $taskStartTime | Out-File -FilePath "$taskDir\task_start.txt" -Force
    Write-Host "Task start timestamp: $taskStartTime"

    # ---------------------------------------------------------------
    # 4. Verify DICOM data is present
    # ---------------------------------------------------------------
    $dicomDir = "C:\Users\Docker\Documents\DentalDICOM"
    if (Test-Path $dicomDir) {
        $dicomCount = (Get-ChildItem $dicomDir -File | Measure-Object).Count
        Write-Host "DICOM directory found with $dicomCount files"
    } else {
        Write-Host "WARNING: DICOM directory not found at $dicomDir"
    }

    # ---------------------------------------------------------------
    # 5. Ensure Mesa software OpenGL is configured
    # ---------------------------------------------------------------
    try { Setup-MesaOpenGL } catch { Write-Host "WARNING: Setup-MesaOpenGL: $($_.Exception.Message)" }

    # ---------------------------------------------------------------
    # 6. Launch Blue Sky Plan fresh (agent will import DICOM)
    # ---------------------------------------------------------------
    $bspExe = Find-BlueSkyPlanExe
    Write-Host "Blue Sky Plan executable: $bspExe"
    Write-Host "Launching Blue Sky Plan fresh (agent must perform full workflow)..."
    Launch-BlueSkyPlanInteractive -BSPExe $bspExe -WaitSeconds 25

    # ---------------------------------------------------------------
    # 7. Dismiss any startup dialogs
    # ---------------------------------------------------------------
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) { & $dismissScript }

    # ---------------------------------------------------------------
    # 8. Verify BSP is running
    # ---------------------------------------------------------------
    $bspProc = Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*Launcher*"
    } | Select-Object -First 1
    if ($bspProc) {
        Write-Host "Blue Sky Plan is running (PID: $($bspProc.Id))"
    } else {
        Write-Host "WARNING: Blue Sky Plan process not found after launch."
    }

    Write-Host "=== complete_implant_workflow task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
