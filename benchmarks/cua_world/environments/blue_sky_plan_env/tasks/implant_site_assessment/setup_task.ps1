# Setup script for implant_site_assessment task.
# Launches Blue Sky Plan fresh, creates output directories,
# records task start timestamp, and verifies DICOM data exists.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_implant_site_assessment.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up implant_site_assessment task ==="

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

    # ---- Ensure output directories exist and clean previous outputs ----
    $taskDir = "C:\Users\Docker\Desktop\BlueSkyPlanTasks"
    New-Item -ItemType Directory -Force -Path $taskDir | Out-Null

    $imagesDir = "$taskDir\site_images"
    if (Test-Path $imagesDir) {
        Remove-Item "$imagesDir\*" -Force -Recurse -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $imagesDir | Out-Null

    # Clean previous output files for this task
    $outputBsp = "$taskDir\site_assessment.bsp"
    $resultJson = "$taskDir\site_assessment_result.json"
    foreach ($f in @($outputBsp, $resultJson)) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }

    # ---- Record task start timestamp for anti-gaming verification ----
    $taskStartTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $taskStartTime | Out-File -FilePath "$taskDir\task_start.txt" -Force
    Write-Host "Task start timestamp: $taskStartTime"

    # ---- Verify DICOM data exists ----
    $dicomDir = "C:\Users\Docker\Documents\DentalDICOM"
    if (Test-Path $dicomDir) {
        $dicomFiles = @(Get-ChildItem -Path $dicomDir -File -ErrorAction SilentlyContinue)
        Write-Host "DICOM directory found: $dicomDir ($($dicomFiles.Count) files)"
    } else {
        Write-Host "WARNING: DICOM directory not found at $dicomDir"
    }

    # ---- Ensure Mesa OpenGL is set up (required for software rendering in QEMU) ----
    try { Setup-MesaOpenGL } catch { Write-Host "WARNING: Setup-MesaOpenGL: $($_.Exception.Message)" }

    # ---- Find and launch Blue Sky Plan ----
    $bspExe = Find-BlueSkyPlanExe
    Write-Host "Blue Sky Plan executable: $bspExe"
    Write-Host "Launching Blue Sky Plan (agent will need to load DICOM data)..."
    Launch-BlueSkyPlanInteractive -BSPExe $bspExe -WaitSeconds 25

    # ---- Dismiss any startup dialogs ----
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        & $dismissScript
    }

    # ---- Verify Blue Sky Plan is running ----
    $bspProc = Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*Launcher*"
    } | Select-Object -First 1
    if ($bspProc) {
        Write-Host "Blue Sky Plan is running (PID: $($bspProc.Id))"
    } else {
        Write-Host "WARNING: Blue Sky Plan process not found after launch."
    }

    Write-Host "=== implant_site_assessment task setup complete ==="
    Write-Host "Agent should now:"
    Write-Host "  1. Load DICOM data from C:\Users\Docker\Documents\DentalDICOM"
    Write-Host "  2. Navigate to lower right posterior jaw sites"
    Write-Host "  3. Measure vertical bone height and buccolingual width at 3 sites"
    Write-Host "  4. Place annotations/markers at each assessment site"
    Write-Host "  5. Save project to C:\Users\Docker\Desktop\BlueSkyPlanTasks\site_assessment.bsp"
    Write-Host "  6. Export cross-sectional views to C:\Users\Docker\Desktop\BlueSkyPlanTasks\site_images\"
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
