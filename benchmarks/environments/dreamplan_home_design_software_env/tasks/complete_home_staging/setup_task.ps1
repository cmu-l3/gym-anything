# Setup script for complete_home_staging task.
# Real estate stager task: furnish living room, dining room, and bedroom,
# then export a separate 3D view image for each furnished room.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_complete_home_staging.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up complete_home_staging task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    Start-EdgeKillerTask
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Remove any leftover result/output files from previous runs (clean slate)
    $filesToClean = @(
        "C:\Users\Docker\Desktop\staged_living_room.jpg",
        "C:\Users\Docker\Desktop\staged_dining_room.jpg",
        "C:\Users\Docker\Desktop\staged_bedroom.jpg",
        "C:\Users\Docker\complete_home_staging_result.json"
    )
    foreach ($f in $filesToClean) {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }

    # Record task start timestamp AFTER cleaning output files
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_home_staging.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Ensure DreamPlan is running with the Contemporary House project loaded
    Write-Host "Ensuring DreamPlan is ready for task..."
    $ready = Ensure-DreamPlanReadyForTask
    if (-not $ready) {
        Write-Host "WARNING: Could not fully verify DreamPlan state. Proceeding anyway."
    }

    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-EdgeKillerTask

    Write-Host "=== complete_home_staging setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
