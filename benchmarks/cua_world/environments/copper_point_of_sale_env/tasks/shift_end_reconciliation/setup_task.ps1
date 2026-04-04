Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_shift_end_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up shift_end_reconciliation task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # Stop any running Copper instance for a clean slate
    Stop-Copper

    $taskDataDir = "C:\workspace\tasks\shift_end_reconciliation"
    $desktopDir  = "C:\Users\Docker\Desktop"
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null

    # Stage shift inventory CSV on Desktop
    $shiftItemsCSV = Join-Path $taskDataDir "shift_items.csv"
    if (Test-Path $shiftItemsCSV) {
        Copy-Item $shiftItemsCSV -Destination (Join-Path $desktopDir "shift_items.csv") -Force
        Write-Host "Staged shift_items.csv on Desktop."
    } else {
        Write-Host "WARNING: shift_items.csv not found."
    }

    # Stage shift log text file on Desktop
    $shiftLog = Join-Path $taskDataDir "shift_log.txt"
    if (Test-Path $shiftLog) {
        Copy-Item $shiftLog -Destination (Join-Path $desktopDir "shift_log.txt") -Force
        Write-Host "Staged shift_log.txt on Desktop."
    } else {
        Write-Host "WARNING: shift_log.txt not found."
    }

    # Remove any leftover output files
    Remove-Item "C:\Users\Docker\shift_end_result.json" -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $desktopDir "shift_report.csv") -Force -ErrorAction SilentlyContinue

    # Record task start timestamp
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_shift_end.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Launch Copper POS
    Write-Host "Launching Copper POS..."
    Launch-CopperInteractive -WaitSeconds 20

    & "C:\workspace\scripts\dismiss_dialogs.ps1"

    Wait-ForCopperProcess -TimeoutSeconds 30

    Minimize-Terminals

    Write-Host "=== shift_end_reconciliation setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
