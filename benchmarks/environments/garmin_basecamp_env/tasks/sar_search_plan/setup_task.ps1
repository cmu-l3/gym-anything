######################################################################
# setup_task.ps1  -  pre_task hook for sar_search_plan
# Start state: BaseCamp open with fells_loop terrain data loaded
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_sar_search_plan.log" -Append | Out-Null
Write-Host "=== Setting up sar_search_plan task ==="

. "C:\workspace\scripts\task_utils.ps1"

Close-Browsers
Close-BaseCamp

# Restore BaseCamp data with fells_loop terrain reference data
$restored = Restore-BaseCampData
if (-not $restored) {
    Write-Host "WARNING: Could not restore BaseCamp data"
}

# Record task start timestamp
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\GarminTools\sar_search_plan_start_ts.txt" -Encoding ASCII
Write-Host "Task start timestamp: $taskStart"

# Remove any leftover export file from a previous run
$exportPath = "C:\Users\Docker\Desktop\SAR_Middlesex_Fells_2024.gpx"
if (Test-Path $exportPath) { Remove-Item $exportPath -Force }

# Launch BaseCamp (Task Launcher dismissed automatically via Plan a Trip click)
$bcOk = Launch-BaseCampInteractive -WaitSeconds 80

Close-Browsers

Write-Host "=== sar_search_plan task setup complete ==="
Stop-Transcript | Out-Null
