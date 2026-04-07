# Shared pre-task launch script for StudioTax 2024.
# Called by each task's setup_task.ps1 to relaunch StudioTax before the agent starts.
# Pattern follows crypto_day_trader_return/setup_task.ps1 which is known to work.

$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Pre-task: Launching StudioTax 2024 ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # Kill any existing StudioTax instances
    $ErrorActionPreference = "Continue"
    Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $ErrorActionPreference = "Stop"

    # Find and launch StudioTax
    $studioTaxExe = Find-StudioTaxExe
    if (-not $studioTaxExe) {
        Write-Host "ERROR: StudioTax executable not found"
        exit 1
    }
    Write-Host "StudioTax: $studioTaxExe"

    Launch-StudioTaxInteractive -StudioTaxExe $studioTaxExe -WaitSeconds 15

    # Dismiss startup dialogs
    $taskName = "DismissDialogs_PreTask"
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN $taskName /TR "powershell -ExecutionPolicy Bypass -File C:\workspace\scripts\dismiss_dialogs.ps1" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN $taskName 2>$null
    Start-Sleep -Seconds 15
    schtasks /Delete /TN $taskName /F 2>$null
    $ErrorActionPreference = "Stop"

    # Verify StudioTax is running
    $proc = Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { Write-Host "StudioTax running (PID: $($proc.Id))" }
    else { Write-Host "WARNING: StudioTax process not detected" }

    Write-Host "=== Pre-task launch complete ==="
} catch {
    Write-Host "ERROR in pre-task: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
