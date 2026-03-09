# Setup script for second_floor_addition task.
# Residential architect task: add a second floor to the Contemporary House,
# create rooms, add staircase, export floor plans for both levels + 3D exterior.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_second_floor_addition.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up second_floor_addition task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    Start-EdgeKillerTask
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Remove any leftover result/output files from previous runs (clean slate)
    $filesToClean = @(
        "C:\Users\Docker\Desktop\ground_floor_plan.jpg",
        "C:\Users\Docker\Desktop\second_floor_plan.jpg",
        "C:\Users\Docker\Desktop\two_story_exterior.jpg",
        "C:\Users\Docker\Documents\two_story_design.dpn",
        "C:\Users\Docker\second_floor_addition_result.json"
    )
    foreach ($f in $filesToClean) {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }

    # Ensure Documents directory exists for project save
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null

    # Record task start timestamp AFTER cleaning output files
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_second_floor.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Ensure DreamPlan is running with the Contemporary House project loaded
    Write-Host "Ensuring DreamPlan is ready for task..."
    $ready = Ensure-DreamPlanReadyForTask
    if (-not $ready) {
        Write-Host "WARNING: Could not fully verify DreamPlan state. Proceeding anyway."
    }

    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-EdgeKillerTask

    Write-Host "=== second_floor_addition setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
