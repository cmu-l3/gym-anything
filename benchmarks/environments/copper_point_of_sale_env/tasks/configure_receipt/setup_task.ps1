# Setup script for configure_receipt task.
# Ensures Copper POS is open and ready for receipt configuration.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_configure_receipt.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up configure_receipt task ==="

    # Load shared helpers
    . "C:\workspace\scripts\task_utils.ps1"

    # Close any existing Copper POS for clean state
    Stop-Copper

    # Launch Copper POS in interactive desktop session
    Write-Host "Launching Copper POS..."
    Launch-CopperInteractive -WaitSeconds 20

    # Dismiss any startup dialogs
    & "C:\workspace\scripts\dismiss_dialogs.ps1"

    # Wait for Copper process
    Wait-ForCopperProcess -TimeoutSeconds 30

    # Minimize terminal windows
    Minimize-Terminals

    Write-Host "=== configure_receipt task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
