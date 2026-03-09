# Setup script for run_backtest task.
# Ensures clean state and opens NinjaTrader 8 Control Center with MSFT data available.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_run_backtest.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up run_backtest task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Close any open NinjaTrader windows
    Get-Process NinjaTrader -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Ensure the data file exists on the Desktop
    $dataFile = "C:\Users\Docker\Desktop\NinjaTraderTasks\MSFT.Last.txt"
    if (-not (Test-Path $dataFile)) {
        $destDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item "C:\workspace\data\MSFT.Last.txt" -Destination $dataFile -Force
    }
    Write-Host "Data file ready at: $dataFile"

    # Find and launch NinjaTrader in interactive session
    $ntExe = Find-NTExe
    Write-Host "NinjaTrader executable: $ntExe"
    Write-Host "Launching NinjaTrader via scheduled task (interactive desktop)..."
    Launch-NTInteractive -NTExe $ntExe -WaitSeconds 20

    # Dismiss startup dialogs via PyAutoGUI TCP (runs from Session 0)
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs via PyAutoGUI TCP..."
        & $dismissScript
    }

    # Verify NinjaTrader is running
    $ntProc = Get-Process NinjaTrader -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ntProc) {
        Write-Host "NinjaTrader is running (PID: $($ntProc.Id))"
    } else {
        Write-Host "WARNING: NinjaTrader process not found after launch."
    }

    Write-Host "=== run_backtest task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
