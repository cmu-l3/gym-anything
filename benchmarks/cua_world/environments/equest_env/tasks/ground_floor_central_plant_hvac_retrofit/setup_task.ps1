# Setup script for ground_floor_central_plant_hvac_retrofit task.
# Uses Pattern 1 (lightweight launch) matching heat_pump_conversion_middle_floor.
# Records baselines and timestamps, then launches eQUEST with startup dialog open.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_central_plant_retrofit.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up ground_floor_central_plant_hvac_retrofit task ==="
    . C:\workspace\scripts\task_utils.ps1

    # Clean up stale outputs BEFORE recording timestamp
    $resultFile = "C:\Users\Docker\central_plant_retrofit_result.json"
    if (Test-Path $resultFile) { Remove-Item $resultFile -Force -ErrorAction SilentlyContinue }

    $baselineFile = "C:\Users\Docker\baseline_central_plant_retrofit.json"
    if (Test-Path $baselineFile) { Remove-Item $baselineFile -Force -ErrorAction SilentlyContinue }

    # Record task start time for anti-gaming timestamp checks
    $startTs = [int][double]::Parse((Get-Date -UFormat %s))
    Set-Content -Path "C:\Users\Docker\task_start_ts_central_plant_retrofit.txt" -Value $startTs
    Write-Host "Task start timestamp: $startTs"

    # Close any open eQUEST / DOE-2 processes
    Get-Process | Where-Object { $_.ProcessName -like "*quest*" -or $_.ProcessName -like "*doe*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Clean up previous project directory to avoid stale data
    $projDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
    if (Test-Path $projDir) { Remove-Item $projDir -Recurse -Force -ErrorAction SilentlyContinue }

    $inpFile = "C:\Users\Docker\Desktop\eQUEST_Projects\4StoreyBuilding.inp"
    Write-Host "Building model: $inpFile"

    # Verify .inp exists
    if (-not (Test-Path $inpFile)) {
        throw "4StoreyBuilding.inp not found at expected path: $inpFile"
    }

    # Launch eQUEST (leaves startup dialog open for the agent)
    & C:\workspace\scripts\launch_app_pretask.ps1

    Write-Host "=== ground_floor_central_plant_hvac_retrofit setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
