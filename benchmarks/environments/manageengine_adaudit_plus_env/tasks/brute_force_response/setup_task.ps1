Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\setup_brute_force_response.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up brute_force_response task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    $ready = Wait-ForADAudit -TimeoutSec 600
    if (-not $ready) {
        Write-Host "WARNING: ADAudit Plus not ready, proceeding anyway..."
    }

    # --- Task-specific event generation ---
    # Generate 15 failed logon attempts specifically targeting 'rwilliams'
    # This makes rwilliams clearly the most-targeted account in the audit trail
    Write-Host "Generating 15 brute-force failed logon events targeting rwilliams..."
    for ($i = 1; $i -le 15; $i++) {
        try {
            & net use "\\localhost\IPC$" /user:rwilliams "WrongPass$i!" 2>$null
        } catch {}
        Start-Sleep -Milliseconds 300
        if ($i % 5 -eq 0) {
            Write-Host "  Generated $i/15 failed logon events for rwilliams"
        }
    }
    Write-Host "  Done: 15 failed logon events generated for rwilliams"

    # Also add 3 failed logins for jsmith to create noise (rwilliams still dominant)
    Write-Host "Generating 3 noise events for jsmith..."
    for ($i = 1; $i -le 3; $i++) {
        try {
            & net use "\\localhost\IPC$" /user:jsmith "WrongJSmith$i!" 2>$null
        } catch {}
        Start-Sleep -Milliseconds 200
    }

    # Record task start timestamp
    $taskStart = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $taskStart | Out-File "C:\Users\Docker\task_start_timestamp.txt" -Encoding ASCII -NoNewline
    Write-Host "Task start timestamp: $taskStart"

    # Remove any pre-existing analysis file
    $analysisFile = "C:\Users\Docker\Desktop\brute_force_analysis.txt"
    if (Test-Path $analysisFile) {
        Remove-Item $analysisFile -Force
        Write-Host "Removed pre-existing analysis file"
    }

    # Launch Edge to ADAudit Plus
    Launch-BrowserToADAudit -Path "/" -WaitSeconds 20

    Write-Host "=== Setup complete for brute_force_response ==="
} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
