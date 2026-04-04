Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_store_config_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up new_store_configuration task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # Stop any running Copper instance for a clean slate
    Stop-Copper

    $taskDataDir = "C:\workspace\tasks\new_store_configuration"
    $desktopDir  = "C:\Users\Docker\Desktop"
    New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null

    # Stage store specifications file on Desktop
    $storeSpecs = Join-Path $taskDataDir "store_specs.txt"
    if (Test-Path $storeSpecs) {
        Copy-Item $storeSpecs -Destination (Join-Path $desktopDir "store_specs.txt") -Force
        Write-Host "Staged store_specs.txt on Desktop."
    } else {
        Write-Host "WARNING: store_specs.txt not found."
    }

    # Remove any leftover output files from previous runs
    Remove-Item "C:\Users\Docker\new_store_config_result.json" -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $desktopDir "tax_verification.txt") -Force -ErrorAction SilentlyContinue

    # Record task start timestamp
    $ts = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ts | Out-File -FilePath "C:\Users\Docker\task_start_ts_store_config.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $ts"

    # Launch Copper POS (agent must configure from scratch)
    Write-Host "Launching Copper POS..."
    Launch-CopperInteractive -WaitSeconds 20

    & "C:\workspace\scripts\dismiss_dialogs.ps1"

    Wait-ForCopperProcess -TimeoutSeconds 30

    Minimize-Terminals

    Write-Host "=== new_store_configuration setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
