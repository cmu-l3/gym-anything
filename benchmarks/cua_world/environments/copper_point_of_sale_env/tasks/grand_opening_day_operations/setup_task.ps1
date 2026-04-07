Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_grand_opening_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up grand_opening_day_operations task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # Stop any running Copper instance for a clean slate
    Stop-Copper

    $taskDataDir = "C:\workspace\tasks\grand_opening_day_operations"
    $desktopDir  = "C:\Users\Docker\Desktop"
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null

    # Stage inventory CSV on Desktop
    $inventoryCSV = Join-Path $taskDataDir "store_inventory.csv"
    if (Test-Path $inventoryCSV) {
        Copy-Item $inventoryCSV -Destination (Join-Path $desktopDir "store_inventory.csv") -Force
        Write-Host "Staged store_inventory.csv on Desktop."
    } else {
        Write-Host "WARNING: store_inventory.csv not found in $taskDataDir"
    }

    # Remove any leftover output files and result JSON
    Remove-Item "C:\Users\Docker\grand_opening_result.json" -Force -ErrorAction SilentlyContinue
    @("daily_sales_report.csv", "opening_day_summary.txt") | ForEach-Object {
        Remove-Item (Join-Path $desktopDir $_) -Force -ErrorAction SilentlyContinue
    }

    # Record task start timestamp
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_grand_opening.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Launch Copper POS
    Write-Host "Launching Copper POS..."
    Launch-CopperInteractive -WaitSeconds 20

    & "C:\workspace\scripts\dismiss_dialogs.ps1"

    Wait-ForCopperProcess -TimeoutSeconds 30

    Minimize-Terminals

    Write-Host "=== grand_opening_day_operations setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
