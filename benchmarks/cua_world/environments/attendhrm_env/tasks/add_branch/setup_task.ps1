# setup_task.ps1 — add_branch
# Prepares the environment for adding a new branch (Downtown Office).
#
# WHAT IT DOES:
#   - Cleans up any prior "Downtown Office" branch from the database
#   - Launches AttendHRM and navigates to a ready state

$logPath = "C:\Users\Docker\task_setup_add_branch.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up add_branch task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    New-Item -ItemType Directory -Force -Path "C:\temp" | Out-Null

    Stop-AttendHRM
    Start-Sleep -Seconds 2

    $isqlPath = "C:\Program Files (x86)\Firebird\Firebird_5_0\isql.exe"
    $dbPath   = "C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB"

    function Run-Isql {
        param([string]$sql)
        $tmp = "C:\Windows\Temp\isql_setup_$(Get-Random).sql"
        Set-Content -Path $tmp -Value ($sql + "`nCOMMIT;`nEXIT;") -Encoding ASCII
        $out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmp 2>&1
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return $out
    }

    # ---- Cleanup from any prior test run ----
    Write-Host "Cleaning up prior Downtown Office branch if it exists..."
    $cleanup = Run-Isql @"
DELETE FROM WGR_BRA WHERE UPPER(BRA_NAME) LIKE '%DOWNTOWN%OFFICE%';
"@
    Write-Host "Cleanup result: $cleanup"

    # Record setup state
    $state = @{
        expected_name  = "Downtown Office"
        expected_code  = "DTN"
        expected_city  = "San Francisco"
        seeded_at      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $state | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\temp\add_branch_setup.json" -Encoding ASCII
    Write-Host "Setup state saved."

    (Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Set-Content -Path "C:\temp\task_start_timestamp.txt" -Encoding ASCII

    # ---- Launch AttendHRM ----
    Close-Browsers
    $edgeKiller = Start-EdgeKillerTask

    try {
        Launch-AttendHRMInteractive -WaitSeconds 15
        $started = Wait-ForAttendHRM -TimeoutSec 30
        if (-not $started) {
            Write-Host "WARNING: AttendHRM not detected, proceeding anyway"
        }
        Login-AttendHRM -WaitAfterLoginSec 6
        Set-AttendHRMForeground | Out-Null
        Start-Sleep -Seconds 1
        Write-Host "Task ready: AttendHRM logged in, agent should add Downtown Office branch."
    } finally {
        Stop-EdgeKillerTask -KillerInfo $edgeKiller
    }

    Write-Host "=== add_branch setup complete ==="

} catch {
    Write-Host "ERROR in setup_task.ps1: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
