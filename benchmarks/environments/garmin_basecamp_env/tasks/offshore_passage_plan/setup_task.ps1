######################################################################
# setup_task.ps1  -  pre_task hook for offshore_passage_plan
# Start state: BaseCamp open with EMPTY library (clean slate)
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_offshore.log" -Append | Out-Null
Write-Host "=== Setting up offshore_passage_plan task ==="

. "C:\workspace\scripts\task_utils.ps1"

Close-Browsers
Close-BaseCamp

# Clear BaseCamp database — agent creates all data from scratch
Clear-BaseCampData

# Record task start timestamp
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\GarminTools\offshore_start_ts.txt" -Encoding ASCII
Write-Host "Task start timestamp: $taskStart"

# Remove any leftover export from previous run
$exportPath = "C:\Users\Docker\Desktop\Newport_Bermuda_2024_PassagePlan.gpx"
if (Test-Path $exportPath) { Remove-Item $exportPath -Force }

# Launch BaseCamp with empty library
$bcOk = Launch-BaseCampInteractive -WaitSeconds 80

Close-Browsers

Write-Host "=== offshore_passage_plan task setup complete ==="
Stop-Transcript | Out-Null
