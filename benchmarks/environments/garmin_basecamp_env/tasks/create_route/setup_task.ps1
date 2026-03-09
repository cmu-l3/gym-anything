######################################################################
# setup_task.ps1  -  pre_task hook for create_route
# Start state: BaseCamp open with Fells Loop waypoints available
######################################################################
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\GarminTools\task_create_route.log" -Append | Out-Null
Write-Host "=== Setting up create_route task ==="

. "C:\workspace\scripts\task_utils.ps1"

Close-Browsers
Close-BaseCamp

# Restore BaseCamp data with Fells Loop imported
$restored = Restore-BaseCampData
if (-not $restored) {
    Write-Host "WARNING: Could not restore BaseCamp data"
}

# Launch BaseCamp (Task Launcher dismissed automatically via Plan a Trip click)
$bcOk = Launch-BaseCampInteractive -WaitSeconds 80

# Window management (minimize PyAutoGUI terminal, bring BaseCamp to front,
# zoom to Fells data) is handled inside Launch-BaseCampInteractive via schtasks /IT.
Close-Browsers

Write-Host "=== create_route task setup complete ==="
Stop-Transcript | Out-Null
