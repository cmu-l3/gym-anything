######################################################################
# setup_task.ps1  -  pre_task hook for tactical_patrol_routes
# Start state: BaseCamp open with EMPTY library (clean slate)
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_tactical.log" -Append | Out-Null
Write-Host "=== Setting up tactical_patrol_routes task ==="

. "C:\workspace\scripts\task_utils.ps1"

Close-Browsers
Close-BaseCamp

# Clear BaseCamp database — agent creates all data from scratch
Clear-BaseCampData

# Record task start timestamp
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\GarminTools\tactical_start_ts.txt" -Encoding ASCII
Write-Host "Task start timestamp: $taskStart"

# Remove any leftover export from previous run
$exportPath = "C:\Users\Docker\Desktop\TacOp_Exercise_Foxtrot.gpx"
if (Test-Path $exportPath) { Remove-Item $exportPath -Force }

# Launch BaseCamp with empty library
$bcOk = Launch-BaseCampInteractive -WaitSeconds 80

Close-Browsers

Write-Host "=== tactical_patrol_routes task setup complete ==="
Stop-Transcript | Out-Null
