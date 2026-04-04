Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\setup_investigate_account_activity.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up investigate_account_activity task ==="

    # Load shared utilities
    . "C:\workspace\scripts\task_utils.ps1"

    # Wait for ADAudit Plus to be ready
    $ready = Wait-ForADAudit -TimeoutSec 600
    if (-not $ready) {
        Write-Host "WARNING: ADAudit Plus not ready, proceeding anyway..."
    }

    # --- Task-specific Windows event generation ---
    # Generate additional failed logon events specifically targeting 'dlee'
    # This makes dlee clearly the most-targeted account
    Write-Host "Generating task-specific security events..."

    for ($i = 1; $i -le 10; $i++) {
        try {
            & net use "\\localhost\IPC$" /user:dlee "WrongPassword$i!" 2>$null
        } catch {}
        Start-Sleep -Milliseconds 200
    }
    Write-Host "  Generated 10 additional failed logon events for dlee"

    # Modify user mjohnson's description (generates Event ID 4738 — User Account Changed)
    try {
        & net user mjohnson /comment:"Security Analyst - Account under review" 2>$null
        Write-Host "  Modified mjohnson account description (Event ID 4738)"
    } catch {
        Write-Host "  Could not modify mjohnson: $_"
    }

    # Also attempt a password reset for dlee (generates Event ID 4724)
    try {
        & net user dlee "TempPass@2024!" 2>$null
        Write-Host "  Password reset for dlee (Event ID 4724)"
    } catch {
        Write-Host "  Could not reset dlee password: $_"
    }

    # Record task start timestamp (Unix epoch seconds for cross-platform comparison)
    $taskStart = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $taskStart | Out-File "C:\Users\Docker\task_start_timestamp.txt" -Encoding ASCII -NoNewline
    Write-Host "Task start timestamp recorded: $taskStart"

    # Ensure any pre-existing report file is removed so we can detect new creation
    $reportFile = "C:\Users\Docker\Desktop\account_threat_report.txt"
    if (Test-Path $reportFile) {
        Remove-Item $reportFile -Force
        Write-Host "Removed pre-existing report file"
    }

    # Launch Edge browser to ADAudit Plus login page
    Launch-BrowserToADAudit -Path "/" -WaitSeconds 20

    Write-Host "=== Setup complete for investigate_account_activity ==="
} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
