# Shared pre-task launch script for eQUEST.
# Called by each task's setup_task.ps1 to relaunch eQUEST before the agent starts.
# Pattern follows change_thermostat_setpoints/setup_task.ps1 which is known to work.
# Note: eQUEST will show its Startup Options dialog — the agent can interact with it.

$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Pre-task: Launching eQUEST ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Kill any existing eQUEST processes
    Get-Process | Where-Object { $_.ProcessName -like "*quest*" -or $_.ProcessName -like "*doe*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Find eQUEST executable
    $eqExe = Find-EqExe
    Write-Host "eQUEST: $eqExe"

    # Launch eQUEST in interactive session (will show Startup Options dialog)
    Launch-EqProjectInteractive -EqExe $eqExe -WaitSeconds 20

    # Dismiss OneDrive popup if present (click "No thanks")
    $ErrorActionPreference = "Continue"
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1167; y = 626} | Out-Null } catch { }
    Start-Sleep -Seconds 1
    $ErrorActionPreference = "Stop"

    # Verify eQUEST is running (leave startup dialog for the agent)
    $proc = Get-Process | Where-Object { $_.ProcessName -like "*quest*" } | Select-Object -First 1
    if ($proc) { Write-Host "eQUEST running (PID: $($proc.Id))" }
    else { Write-Host "WARNING: eQUEST process not found after launch." }

    Write-Host "=== Pre-task launch complete ==="
} catch {
    Write-Host "ERROR in pre-task: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
