######################################################################
# setup_task.ps1  -  pre_task hook for gr7_guided_tour_plan
# Start state: BaseCamp open with EMPTY library; dole_langres_track.gpx on Desktop
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_gr7.log" -Append | Out-Null
Write-Host "=== Setting up gr7_guided_tour_plan task ==="

. "C:\workspace\scripts\task_utils.ps1"

Close-Browsers
Close-BaseCamp

# Clear BaseCamp database — agent must import the track
Clear-BaseCampData

# Record task start timestamp
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Set-Content "C:\GarminTools\gr7_start_ts.txt" -Encoding ASCII
Write-Host "Task start timestamp: $taskStart"

# Place the GR7 track GPX file on the Desktop for the agent to import
$desktopPath = "C:\Users\Docker\Desktop"
New-Item -ItemType Directory -Force -Path $desktopPath | Out-Null
Copy-Item "C:\workspace\data\dole_langres_track.gpx" "$desktopPath\dole_langres_track.gpx" -Force
Write-Host "GPX placed on Desktop: $desktopPath\dole_langres_track.gpx"

# Remove any leftover export from previous run
$exportPath = "C:\Users\Docker\Desktop\GR7_Guide_DoleLangres.gpx"
if (Test-Path $exportPath) { Remove-Item $exportPath -Force }

# Launch BaseCamp with empty library
$bcOk = Launch-BaseCampInteractive -WaitSeconds 80

Close-Browsers

Write-Host "=== gr7_guided_tour_plan task setup complete ==="
Stop-Transcript | Out-Null
