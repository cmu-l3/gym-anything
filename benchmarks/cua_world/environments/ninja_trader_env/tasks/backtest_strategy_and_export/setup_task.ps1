Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_backtest_strategy_and_export.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up backtest_strategy_and_export task ==="

    # Load shared helpers
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) {
        throw "Missing task utils: $utils"
    }
    . $utils

    # Kill any existing NinjaTrader
    Get-Process NinjaTrader -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Ensure task output directory exists
    $outputDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

    # Record baseline: ensure expected output file does NOT exist yet
    $expectedOutput = Join-Path $outputDir "spy_backtest_trades.csv"
    if (Test-Path $expectedOutput) {
        Remove-Item $expectedOutput -Force
        Write-Host "Removed pre-existing output file"
    }

    # Record baseline state
    $baselineInfo = @{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        output_file_existed = $false
    }
    $baselineInfo | ConvertTo-Json | Out-File "$outputDir\backtest_baseline.json" -Encoding utf8

    # Record task start timestamp
    [int](Get-Date -UFormat %s) | Out-File "$outputDir\task_start_timestamp.txt" -Encoding utf8

    # Verify SPY data exists in NinjaTrader DB
    $spyDataDir = "C:\Users\Docker\Documents\NinjaTrader 8\db\day\SPY"
    if (Test-Path $spyDataDir) {
        Write-Host "SPY data directory exists: $spyDataDir"
    } else {
        Write-Host "WARNING: SPY data directory not found at $spyDataDir"
    }

    # Launch NinjaTrader
    $ntExe = Find-NTExe
    Write-Host "NinjaTrader executable: $ntExe"
    Launch-NTInteractive -NTExe $ntExe -WaitSeconds 20

    # Dismiss startup dialogs
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        Write-Host "Dismissing dialogs..."
        & $dismissScript
    }

    # Verify NinjaTrader is running
    $ntProc = Get-Process NinjaTrader -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ntProc) {
        Write-Host "NinjaTrader is running (PID: $($ntProc.Id))"
    } else {
        Write-Host "WARNING: NinjaTrader process not found."
    }

    Write-Host "=== backtest_strategy_and_export task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
