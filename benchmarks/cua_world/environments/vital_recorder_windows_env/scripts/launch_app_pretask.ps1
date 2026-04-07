# Shared pre-task launch script for Vital Recorder.
# Called by each task's setup_task.ps1 to relaunch Vital Recorder before the agent starts.
# Pattern follows open_vital_file/setup_task.ps1 which is known to work.

$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Pre-task: Launching Vital Recorder ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # Kill any existing Vital Recorder processes (process name is "Vital")
    Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Find and launch Vital Recorder
    $vrExe = Find-VitalRecorderExe
    Write-Host "Vital Recorder: $vrExe"

    Launch-VitalRecorderInteractive -VitalRecorderExe $vrExe -WaitSeconds 15

    # Dismiss any dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Run-InteractiveScript -ScriptPath $dismissScript -TaskName "DismissDialogs_PreTask" -WaitSeconds 12
    }

    # Verify Vital Recorder is running
    if (Test-VitalRecorderRunning) {
        Write-Host "Vital Recorder is running"
    } else {
        Write-Host "WARNING: Vital Recorder process not found"
    }

    Write-Host "=== Pre-task launch complete ==="
} catch {
    Write-Host "ERROR in pre-task: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
