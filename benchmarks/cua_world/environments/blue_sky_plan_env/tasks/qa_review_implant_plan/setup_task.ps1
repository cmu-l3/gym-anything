# Setup script for qa_review_implant_plan task.
# Launches Blue Sky Plan with the qa_review_case.bsp project file pre-loaded.
# The case contains a pre-placed implant at tooth #30 with deliberate safety
# violations that the agent must discover, correct, and document.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_qa_review_implant_plan.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up qa_review_implant_plan task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # ---------------------------------------------------------------
    # 1. Kill any existing Blue Sky Plan / NATS / Edge processes
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
    $outputDir = "C:\Users\Docker\Documents\QAReview"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    # Remove previous outputs for this task (BEFORE recording timestamp)
    $outputFiles = @(
        "$outputDir\reviewed_plan.bsp",
        "$outputDir\before_correction.png",
        "$outputDir\after_correction.png",
        "$outputDir\qa_report.txt",
        "$outputDir\qa_review_result.json"
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
    $taskStartTime | Out-File -FilePath "$outputDir\task_start.txt" -Force
    Write-Host "Task start timestamp: $taskStartTime"

    # ---------------------------------------------------------------
    # 4. Verify project file exists
    # ---------------------------------------------------------------
    $projectFile = "C:\workspace\data\qa_review_case.bsp"
    if (Test-Path $projectFile) {
        $fileInfo = Get-Item $projectFile
        Write-Host "Project file found: $projectFile ($($fileInfo.Length) bytes)"
    } else {
        Write-Host "WARNING: Project file not found at $projectFile"
    }

    # ---------------------------------------------------------------
    # 5. Ensure Mesa software OpenGL is configured
    # ---------------------------------------------------------------
    try { Setup-MesaOpenGL } catch { Write-Host "WARNING: Setup-MesaOpenGL: $($_.Exception.Message)" }

    # ---------------------------------------------------------------
    # 6. Launch Blue Sky Plan with the project file
    # ---------------------------------------------------------------
    $bspExe = Find-BlueSkyPlanExe
    Write-Host "Blue Sky Plan executable: $bspExe"
    Write-Host "Launching Blue Sky Plan with $projectFile..."
    Launch-BlueSkyPlanWithFile -BSPExe $bspExe -FilePath $projectFile -WaitSeconds 30

    # ---------------------------------------------------------------
    # 7. Dismiss any startup dialogs
    # ---------------------------------------------------------------
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        & $dismissScript
    }

    # ---------------------------------------------------------------
    # 8. Additional late-Edge cleanup
    # ---------------------------------------------------------------
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

    # ---------------------------------------------------------------
    # 9. Verify BSP is running
    # ---------------------------------------------------------------
    $bspProc = Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*Launcher*"
    } | Select-Object -First 1
    if ($bspProc) {
        Write-Host "Blue Sky Plan is running (PID: $($bspProc.Id))"
    } else {
        Write-Host "WARNING: Blue Sky Plan process not found after launch."
    }

    Write-Host "=== qa_review_implant_plan task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
