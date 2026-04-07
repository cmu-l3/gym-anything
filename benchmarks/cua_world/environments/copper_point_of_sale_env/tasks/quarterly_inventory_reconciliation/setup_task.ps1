Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_quarterly_reconciliation_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up quarterly_inventory_reconciliation task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # Stop any running Copper instance for a clean slate
    Stop-Copper

    $taskDataDir = "C:\workspace\tasks\quarterly_inventory_reconciliation"
    $desktopDir  = "C:\Users\Docker\Desktop"
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null

    # Stage store inventory CSV on Desktop (agent will import this into Copper)
    $storeInventoryCSV = Join-Path $taskDataDir "store_inventory.csv"
    if (Test-Path $storeInventoryCSV) {
        Copy-Item $storeInventoryCSV -Destination (Join-Path $desktopDir "store_inventory.csv") -Force
        Write-Host "Staged store_inventory.csv on Desktop."
    } else {
        Write-Host "WARNING: store_inventory.csv not found in task directory."
    }

    # Stage physical count CSV on Desktop (agent will compare against imported inventory)
    $physicalCountCSV = Join-Path $taskDataDir "physical_count.csv"
    if (Test-Path $physicalCountCSV) {
        Copy-Item $physicalCountCSV -Destination (Join-Path $desktopDir "physical_count.csv") -Force
        Write-Host "Staged physical_count.csv on Desktop."
    } else {
        Write-Host "WARNING: physical_count.csv not found in task directory."
    }

    # Remove any leftover output files BEFORE recording timestamp
    Remove-Item "C:\Users\Docker\quarterly_reconciliation_result.json" -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $desktopDir "final_inventory.csv") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $desktopDir "quarterly_close.txt") -Force -ErrorAction SilentlyContinue

    # Record task start timestamp
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_quarterly_reconciliation.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Launch Copper POS
    Write-Host "Launching Copper POS..."
    Launch-CopperInteractive -WaitSeconds 20

    & "C:\workspace\scripts\dismiss_dialogs.ps1"

    Wait-ForCopperProcess -TimeoutSeconds 30

    Minimize-Terminals

    Write-Host "=== quarterly_inventory_reconciliation setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
