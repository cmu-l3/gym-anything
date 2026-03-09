Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_optimize_strategy_parameters.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up optimize_strategy_parameters task ==="

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

    # Remove any pre-existing output file
    $expectedOutput = Join-Path $outputDir "msft_optimization_results.csv"
    if (Test-Path $expectedOutput) {
        Remove-Item $expectedOutput -Force
        Write-Host "Removed pre-existing output file"
    }

    # Record baseline
    $baselineInfo = @{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        output_file_existed = $false
    }
    $baselineInfo | ConvertTo-Json | Out-File "$outputDir\optimization_baseline.json" -Encoding utf8

    # Record task start timestamp
    [int](Get-Date -UFormat %s) | Out-File "$outputDir\task_start_timestamp.txt" -Encoding utf8

    # Verify MSFT data exists
    $msftDataDir = "C:\Users\Docker\Documents\NinjaTrader 8\db\day\MSFT"
    if (Test-Path $msftDataDir) {
        Write-Host "MSFT data directory exists: $msftDataDir"
    } else {
        Write-Host "WARNING: MSFT data directory not found at $msftDataDir"
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

    Write-Host "=== optimize_strategy_parameters task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
