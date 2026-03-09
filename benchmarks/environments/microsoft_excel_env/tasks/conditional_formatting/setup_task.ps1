# Setup script for conditional_formatting task.
# Ensures clean state and opens the workbook in the interactive desktop session.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_conditional_formatting.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up conditional_formatting task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Close any open Excel windows
    Get-Process EXCEL -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure the data file exists on the Desktop
    $dataFile = "C:\Users\Docker\Desktop\ExcelTasks\sales_report.xlsx"
    if (-not (Test-Path $dataFile)) {
        $destDir = "C:\Users\Docker\Desktop\ExcelTasks"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item "C:\workspace\data\sales_report.xlsx" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Find Excel and launch the workbook interactively
    $excelExe = Find-ExcelExe
    Write-Host "Excel executable: $excelExe"
    Write-Host "Launching Excel via scheduled task (interactive desktop)..."
    Launch-ExcelWorkbookInteractive -ExcelExe $excelExe -WorkbookPath $dataFile -WaitSeconds 12

    # Best-effort: dismiss common first-run dialogs using the PyAutoGUI server
    # (which runs in the interactive desktop session).
    Write-Host "Dismissing dialogs via PyAutoGUI server..."
    try {
        Dismiss-ExcelDialogsBestEffort
        Write-Host "Dialog dismissal complete."
    } catch {
        Write-Host "WARNING: Dialog dismissal failed: $($_.Exception.Message)"
    }

    # Verify Excel is running
    $excelProc = Get-Process EXCEL -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($excelProc) {
        Write-Host "Excel is running (PID: $($excelProc.Id))"
    } else {
        Write-Host "WARNING: Excel process not found after launch."
    }

    Write-Host "=== conditional_formatting task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
