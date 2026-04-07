# Shared pre-task launch script for Epi Info 7.
# Called by each task's setup_task.ps1 to relaunch Epi Info before the agent starts.
# Pattern follows run_frequency_analysis/setup_task.ps1 which is known to work.

$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Pre-task: Launching Epi Info 7 ==="

    . C:\workspace\scripts\task_utils.ps1

    # Start Edge killer to prevent browser popups
    $edgeKiller = Start-EdgeKillerTask

    # Kill any existing Epi Info processes
    Close-Browsers
    Stop-EpiInfo

    # Launch Epi Info 7 main launcher (no specific module)
    Write-Host "Launching Epi Info 7..."
    Launch-EpiInfoInteractive -WaitSeconds 20

    # Dismiss any startup dialogs (license, update check, etc.)
    Dismiss-EpiInfoDialogs -Retries 3 -WaitSeconds 2

    # Stop Edge killer task
    Stop-EdgeKillerTask -KillerInfo $edgeKiller

    # Verify process is running
    $proc = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "*EpiInfo*" -or $_.ProcessName -like "*Analysis*" -or
        $_.ProcessName -like "*Enter*" -or $_.ProcessName -like "*Menu*"
    } | Select-Object -First 1
    if ($proc) { Write-Host "Epi Info running (PID: $($proc.Id), Name: $($proc.ProcessName))" }
    else { Write-Host "WARNING: Epi Info process not found after launch." }

    Write-Host "=== Pre-task launch complete ==="
} catch {
    Write-Host "ERROR in pre-task: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
