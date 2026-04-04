# Setup script for change_flooring_material task.
# Launches DreamPlan with the built-in Contemporary House sample project in 3D view.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_change_flooring_material.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up change_flooring_material task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    # Start Edge killer to prevent browser interference
    Start-EdgeKillerTask

    # Kill any browsers
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure DreamPlan is running with Contemporary House loaded and no overlays.
    # Uses window title as ground truth. Falls back to full launch+navigate if needed.
    Write-Host "Ensuring DreamPlan is ready for task..."
    $ready = Ensure-DreamPlanReadyForTask
    if (-not $ready) {
        Write-Host "WARNING: Could not verify DreamPlan state. Proceeding anyway."
    }

    # Kill browsers again (Edge may have auto-restored)
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Stop Edge killer
    Stop-EdgeKillerTask

    Write-Host "=== change_flooring_material task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
