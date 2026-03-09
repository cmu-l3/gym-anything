# Setup script for construction_document_set task.
# General contractor task: export 4 different view types (front elevation,
# side elevation, floor plan, 3D overview) and save project.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_construction_document_set.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up construction_document_set task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    Start-EdgeKillerTask
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Remove any leftover result/output files from previous runs (clean slate)
    $filesToClean = @(
        "C:\Users\Docker\Desktop\elevation_front.jpg",
        "C:\Users\Docker\Desktop\elevation_side.jpg",
        "C:\Users\Docker\Desktop\construction_floor_plan.jpg",
        "C:\Users\Docker\Desktop\construction_overview.jpg",
        "C:\Users\Docker\Documents\construction_docs.dpn",
        "C:\Users\Docker\construction_document_set_result.json"
    )
    foreach ($f in $filesToClean) {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }

    # Ensure Documents directory exists for project save
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null

    # Record task start timestamp AFTER cleaning output files
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_construction.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Ensure DreamPlan is running with the Contemporary House project loaded
    Write-Host "Ensuring DreamPlan is ready for task..."
    $ready = Ensure-DreamPlanReadyForTask
    if (-not $ready) {
        Write-Host "WARNING: Could not fully verify DreamPlan state. Proceeding anyway."
    }

    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-EdgeKillerTask

    Write-Host "=== construction_document_set setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
