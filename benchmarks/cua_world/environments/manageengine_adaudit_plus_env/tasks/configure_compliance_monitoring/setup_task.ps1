Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\setup_configure_compliance_monitoring.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up configure_compliance_monitoring task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    $ready = Wait-ForADAudit -TimeoutSec 600
    if (-not $ready) {
        Write-Host "WARNING: ADAudit Plus not ready, proceeding anyway..."
    }

    # --- Task-specific event generation for unique starting state ---
    # Generate additional file access events to C:\AuditTestFolder\Confidential\
    Write-Host "Generating task-specific file access events..."
    try {
        $confFile = "C:\AuditTestFolder\Confidential\financial_report_q4.txt"
        if (Test-Path $confFile) {
            Get-Content $confFile | Out-Null
            Add-Content $confFile "`n# Compliance review pending - Q4 data"
            Write-Host "  Accessed and modified financial_report_q4.txt (file access events)"
        }
        $perfFile = "C:\AuditTestFolder\Confidential\performance_reviews.txt"
        if (Test-Path $perfFile) {
            Get-Content $perfFile | Out-Null
            Write-Host "  Accessed performance_reviews.txt (file access event)"
        }
    } catch {
        Write-Host "  File event generation: $_"
    }

    # Record task start timestamp
    $taskStart = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $taskStart | Out-File "C:\Users\Docker\task_start_timestamp.txt" -Encoding ASCII -NoNewline
    Write-Host "Task start timestamp: $taskStart"

    # Launch Edge to ADAudit Plus
    Launch-BrowserToADAudit -Path "/" -WaitSeconds 20

    Write-Host "=== Setup complete for configure_compliance_monitoring ==="
} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
