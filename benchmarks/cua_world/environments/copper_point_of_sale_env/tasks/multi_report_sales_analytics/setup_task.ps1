Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_multi_report_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up multi_report_sales_analytics task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # Stop any running Copper instance for a clean slate
    Stop-Copper

    $taskDataDir = "C:\workspace\tasks\multi_report_sales_analytics"
    $desktopDir  = "C:\Users\Docker\Desktop"
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null

    # Stage electronics + clothing inventory CSV on Desktop
    $inventoryCSV = Join-Path $taskDataDir "electronics_clothing_inventory.csv"
    if (Test-Path $inventoryCSV) {
        Copy-Item $inventoryCSV -Destination (Join-Path $desktopDir "electronics_clothing_inventory.csv") -Force
        Write-Host "Staged electronics_clothing_inventory.csv on Desktop."
    } else {
        Write-Host "WARNING: electronics_clothing_inventory.csv not found."
    }

    # Stage the analytics brief on Desktop
    $analyticsBrief = Join-Path $taskDataDir "analytics_brief.txt"
    if (Test-Path $analyticsBrief) {
        Copy-Item $analyticsBrief -Destination (Join-Path $desktopDir "analytics_brief.txt") -Force
        Write-Host "Staged analytics_brief.txt on Desktop."
    } else {
        Write-Host "WARNING: analytics_brief.txt not found."
    }

    # Remove any leftover output files
    Remove-Item "C:\Users\Docker\multi_report_result.json" -Force -ErrorAction SilentlyContinue
    @("weekly_sales.csv", "stock_levels.csv", "analytics_summary.txt") | ForEach-Object {
        Remove-Item (Join-Path $desktopDir $_) -Force -ErrorAction SilentlyContinue
    }

    # Record task start timestamp
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_multi_report.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Launch Copper POS
    Write-Host "Launching Copper POS..."
    Launch-CopperInteractive -WaitSeconds 20

    & "C:\workspace\scripts\dismiss_dialogs.ps1"

    Wait-ForCopperProcess -TimeoutSeconds 30

    Minimize-Terminals

    Write-Host "=== multi_report_sales_analytics setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
