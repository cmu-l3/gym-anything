######################################################################
# setup_task.ps1  -  pre_task hook for create_waypoint
# Start state: BaseCamp open with Fells Loop data; map shows the Fells area
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_create_waypoint.log" -Append | Out-Null
Write-Host "=== Setting up create_waypoint task ==="

. "C:\workspace\scripts\task_utils.ps1"

Close-Browsers
Close-BaseCamp

# Restore BaseCamp data with Fells Loop already imported
$restored = Restore-BaseCampData
if (-not $restored) {
    Write-Host "WARNING: Could not restore BaseCamp data - starting with empty library"
}

# Launch BaseCamp (Task Launcher is dismissed automatically via Plan a Trip click)
$bcOk = Launch-BaseCampInteractive -WaitSeconds 80

# Window management (minimize PyAutoGUI terminal, bring BaseCamp to front,
# zoom to Fells data) is handled inside Launch-BaseCampInteractive via schtasks /IT.
Close-Browsers

Write-Host "=== create_waypoint task setup complete ==="
Stop-Transcript | Out-Null
