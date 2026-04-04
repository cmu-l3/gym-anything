Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_seasonal_clearance_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up seasonal_clearance_markdown task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # Stop any running Copper instance for a clean slate
    Stop-Copper

    # Stage the clothing inventory CSV on the Desktop
    $taskDataDir = "C:\workspace\tasks\seasonal_clearance_markdown"
    $desktopDir  = "C:\Users\Docker\Desktop"
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null

    # Copy the clothing inventory CSV to Desktop
    $inventoryCSV = Join-Path $taskDataDir "clothing_inventory.csv"
    if (Test-Path $inventoryCSV) {
        Copy-Item $inventoryCSV -Destination (Join-Path $desktopDir "clothing_inventory.csv") -Force
        Write-Host "Staged clothing_inventory.csv on Desktop."
    } else {
        Write-Host "WARNING: clothing_inventory.csv not found in task directory."
    }

    # Also copy as pricing_reference.csv so agent has a read-only reference
    if (Test-Path $inventoryCSV) {
        Copy-Item $inventoryCSV -Destination (Join-Path $desktopDir "pricing_reference.csv") -Force
        Write-Host "Staged pricing_reference.csv (read-only reference) on Desktop."
    }

    # Remove any leftover result file from a previous run
    Remove-Item "C:\Users\Docker\seasonal_clearance_result.json" -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $desktopDir "clearance_inventory.csv") -Force -ErrorAction SilentlyContinue

    # Record task start timestamp
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_seasonal_clearance.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Launch Copper POS for the agent
    Write-Host "Launching Copper POS..."
    Launch-CopperInteractive -WaitSeconds 20

    & "C:\workspace\scripts\dismiss_dialogs.ps1"

    Wait-ForCopperProcess -TimeoutSeconds 30

    Minimize-Terminals

    Write-Host "=== seasonal_clearance_markdown setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
