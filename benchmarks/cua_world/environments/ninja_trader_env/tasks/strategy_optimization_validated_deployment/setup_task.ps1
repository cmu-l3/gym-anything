Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_strategy_optimization_validated_deployment.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up strategy_optimization_validated_deployment task ==="

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

    # Remove any pre-existing output files (anti-gaming)
    $filesToClean = @(
        (Join-Path $outputDir "qualification_report.txt"),
        (Join-Path $outputDir "qualified_trades.csv"),
        (Join-Path $outputDir "strategy_optimization_validated_deployment_result.json")
    )
    foreach ($f in $filesToClean) {
        if (Test-Path $f) {
            Remove-Item $f -Force
            Write-Host "Removed pre-existing file: $f"
        }
    }

    # Also clean common alternative paths the agent might use
    $altPaths = @(
        "C:\Users\Docker\Desktop\qualification_report.txt",
        "C:\Users\Docker\Documents\qualification_report.txt",
        "C:\Users\Docker\Desktop\qualified_trades.csv",
        "C:\Users\Docker\Documents\qualified_trades.csv"
    )
    foreach ($f in $altPaths) {
        if (Test-Path $f) {
            Remove-Item $f -Force
            Write-Host "Removed alt path file: $f"
        }
    }

    # Remove any pre-existing StrategyQualification workspace
    $wsDir = "$env:USERPROFILE\Documents\NinjaTrader 8\workspaces"
    if (Test-Path $wsDir) {
        Get-ChildItem $wsDir -Filter "StrategyQualification*" -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-Item $_.FullName -Force
                Write-Host "Removed pre-existing workspace: $($_.Name)"
            }
    }

    # Record task start timestamp AFTER deleting stale outputs
    [int](Get-Date -UFormat %s) | Out-File "$outputDir\task_start_timestamp.txt" -Encoding utf8

    # Record baseline workspace state
    $baselineInfo = @{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        workspace_files = @(Get-ChildItem $wsDir -Filter "*.xml" -ErrorAction SilentlyContinue |
                            Select-Object -ExpandProperty Name)
    }
    $baselineInfo | ConvertTo-Json | Out-File "$outputDir\optimization_deployment_baseline.json" -Encoding utf8

    # Verify SPY data exists
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

    Write-Host "=== strategy_optimization_validated_deployment task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
