######################################################################
# setup_task.ps1  -  pre_task hook for import_gpx_file
# Start state: BaseCamp open with empty library; dole_langres_track.gpx on Desktop
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_import_gpx.log" -Append | Out-Null
Write-Host "=== Setting up import_gpx_file task ==="

. "C:\workspace\scripts\task_utils.ps1"

Close-Browsers
Close-BaseCamp

# Clear BaseCamp data so library starts empty (agent must import the file)
Clear-BaseCampData

# Ensure dole_langres_track.gpx is on Desktop
$desktopPath = "C:\Users\Docker\Desktop"
New-Item -ItemType Directory -Force -Path $desktopPath | Out-Null
Copy-Item "C:\workspace\data\dole_langres_track.gpx" "$desktopPath\dole_langres_track.gpx" -Force
Write-Host "GPX file placed on Desktop: $desktopPath\dole_langres_track.gpx"

# Launch BaseCamp with empty library (Task Launcher dismissed automatically)
$bcOk = Launch-BaseCampInteractive -WaitSeconds 80

# Window management (minimize PyAutoGUI terminal, bring BaseCamp to front)
# is handled inside Launch-BaseCampInteractive via schtasks /IT.
Close-Browsers

Write-Host "=== import_gpx_file task setup complete ==="
Stop-Transcript | Out-Null
