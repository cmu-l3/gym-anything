# Shared pre-task launch script for Garmin BaseCamp.
# Called by each task's setup_task.ps1 to relaunch BaseCamp before the agent starts.
# Pattern follows create_waypoint/setup_task.ps1 which is known to work.

$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\task_pre_task.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

Write-Host "=== Pre-task: Launching Garmin BaseCamp ==="

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

Close-Browsers

# Verify BaseCamp is running
$bc = Get-Process "BaseCamp" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($bc) { Write-Host "BaseCamp running (PID: $($bc.Id))" }
else { Write-Host "WARNING: BaseCamp not found after launch." }

Write-Host "=== Pre-task launch complete ==="
try { Stop-Transcript | Out-Null } catch { }
