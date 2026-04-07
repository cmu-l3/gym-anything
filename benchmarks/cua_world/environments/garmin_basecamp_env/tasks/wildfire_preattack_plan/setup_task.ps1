######################################################################
# setup_task.ps1  -  pre_task hook for wildfire_preattack_plan
# Start state: BaseCamp open with fells_loop terrain data loaded
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_wildfire_preattack.log" -Append | Out-Null
Write-Host "=== Setting up wildfire_preattack_plan task ==="

. "C:\workspace\scripts\task_utils.ps1"

Close-Browsers
Close-BaseCamp

# Restore BaseCamp data with fells_loop terrain reference data
$restored = Restore-BaseCampData
if (-not $restored) {
    Write-Host "WARNING: Could not restore BaseCamp data"
}

# Remove any leftover export from previous run
$exportPath = "C:\workspace\output\fells_preattack_2024.gpx"
if (-not (Test-Path "C:\workspace\output")) {
    New-Item -ItemType Directory -Path "C:\workspace\output" -Force | Out-Null
}
if (Test-Path $exportPath) { Remove-Item $exportPath -Force }

# Record task start timestamp
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\GarminTools\wildfire_preattack_start_ts.txt" -Encoding ASCII
Write-Host "Task start timestamp: $taskStart"

# Launch BaseCamp (Task Launcher dismissed automatically via Plan a Trip click)
$bcOk = Launch-BaseCampInteractive -WaitSeconds 80

Close-Browsers

Write-Host "=== wildfire_preattack_plan task setup complete ==="
Stop-Transcript | Out-Null
