# Shared pre-task launch script for Blue Sky Plan.
# Called by each task's setup_task.ps1 to relaunch BSP before the agent starts.

$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Pre-task: Launching Blue Sky Plan ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Kill any existing BSP processes
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or
        $_.ProcessName -like "*Launcher*" -or
        $_.ProcessName -like "*nats-server*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Start-Sleep -Seconds 3

    # Find and launch BSP
    $bspExe = Find-BlueSkyPlanExe
    Write-Host "Blue Sky Plan: $bspExe"

    Launch-BlueSkyPlanInteractive -BSPExe $bspExe -WaitSeconds 30

    # Dismiss hardware warnings, crash reports, login popups
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Running dialog dismissal..."
        & $dismissScript
    }

    Start-Sleep -Seconds 3

    # Verify BSP is running
    $proc = Get-Process | Where-Object { $_.ProcessName -like "*BlueSky*" } | Select-Object -First 1
    if ($proc) { Write-Host "Blue Sky Plan running (PID: $($proc.Id))" }
    else { Write-Host "WARNING: Blue Sky Plan process not found after launch." }

    Write-Host "=== Pre-task launch complete ==="
} catch {
    Write-Host "ERROR in pre-task: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
