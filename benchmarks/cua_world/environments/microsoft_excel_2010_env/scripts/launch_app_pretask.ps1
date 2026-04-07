# Shared pre-task launch script for Microsoft Excel 2010.
# Called by each task's setup_task.ps1 to relaunch Excel before the agent starts.
# Pattern follows conditional_formatting/setup_task.ps1 which is known to work.

$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Pre-task: Launching Microsoft Excel 2010 ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Kill any existing Excel processes
    Get-Process EXCEL -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Find and launch Excel (no document - blank workbook)
    $excelExe = Find-ExcelExe
    Write-Host "Excel: $excelExe"

    Launch-ExcelDocumentInteractive -ExcelExe $excelExe -WaitSeconds 15

    # Dismiss any first-run dialogs
    try { Dismiss-ExcelDialogsBestEffort } catch { Write-Host "WARNING: Dismiss dialogs: $($_.Exception.Message)" }

    # Verify Excel is running
    $proc = Get-Process "EXCEL" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { Write-Host "Excel running (PID: $($proc.Id))" }
    else { Write-Host "WARNING: Excel process not found after launch." }

    Write-Host "=== Pre-task launch complete ==="
} catch {
    Write-Host "ERROR in pre-task: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
