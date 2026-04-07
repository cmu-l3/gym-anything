# Setup script for sunroom_addition task.
# Architect task: add a sunroom to the rear of the Contemporary House,
# with door, windows, wood flooring, furniture, and export 3 views.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_sunroom_addition.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up sunroom_addition task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    Start-EdgeKillerTask
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # ---------- 1. Remove stale output files from previous runs ----------
    $filesToClean = @(
        "C:\Users\Docker\Desktop\sunroom_floorplan.jpg",
        "C:\Users\Docker\Desktop\sunroom_exterior.jpg",
        "C:\Users\Docker\Desktop\sunroom_interior.jpg",
        "C:\Users\Docker\Documents\sunroom_design.dpn",
        "C:\Users\Docker\sunroom_addition_result.json"
    )
    foreach ($f in $filesToClean) {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
    }

    # Ensure Desktop and Documents directories exist
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null

    # ---------- 2. Record task start timestamp AFTER cleaning ----------
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_sunroom.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # ---------- 3. Ensure DreamPlan is ready with Contemporary House ----------
    Write-Host "Ensuring DreamPlan is ready for task..."
    $ready = Ensure-DreamPlanReadyForTask
    if (-not $ready) {
        Write-Host "WARNING: Could not fully verify DreamPlan state. Proceeding anyway."
    }

    # ---------- 4. Kill Edge again ----------
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-EdgeKillerTask

    Write-Host "=== sunroom_addition setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
