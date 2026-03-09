# Setup script for renovation_material_package task.
# Interior designer task: apply differentiated flooring materials across rooms,
# update at least one wall, export 3D view + floor plan, save project.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_renovation_material_package.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up renovation_material_package task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    Start-EdgeKillerTask
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Remove any leftover result/output files from previous runs (clean slate)
    $filesToClean = @(
        "C:\Users\Docker\Desktop\renovation_3d_view.jpg",
        "C:\Users\Docker\Desktop\renovation_floor_plan.jpg",
        "C:\Users\Docker\Documents\renovation_proposal.dpn",
        "C:\Users\Docker\renovation_material_package_result.json"
    )
    foreach ($f in $filesToClean) {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }

    # Ensure Documents directory exists for project save
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null

    # Record task start timestamp AFTER cleaning output files
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_renovation_material.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Ensure DreamPlan is running with the Contemporary House project loaded
    Write-Host "Ensuring DreamPlan is ready for task..."
    $ready = Ensure-DreamPlanReadyForTask
    if (-not $ready) {
        Write-Host "WARNING: Could not fully verify DreamPlan state. Proceeding anyway."
    }

    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-EdgeKillerTask

    Write-Host "=== renovation_material_package setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
