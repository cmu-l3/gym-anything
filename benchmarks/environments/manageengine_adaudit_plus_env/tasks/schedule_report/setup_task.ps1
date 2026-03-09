Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_schedule_report.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up schedule_report task ==="

    # Load shared utilities
    . "C:\workspace\scripts\task_utils.ps1"

    # Wait for ADAudit Plus to be ready
    $ready = Wait-ForADAudit -TimeoutSec 600
    if (-not $ready) {
        Write-Host "WARNING: ADAudit Plus not ready, proceeding anyway..."
    }

    # Launch Edge browser to ADAudit Plus login page
    Launch-BrowserToADAudit -Path "/" -WaitSeconds 20

    Write-Host "=== Task setup complete - browser open to ADAudit Plus ==="
} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
