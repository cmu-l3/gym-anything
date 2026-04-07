# setup_task.ps1 -- new_branch_office_setup
# Prepares the environment for the Manchester branch office setup task.
#
# WHAT IT DOES:
#   - Cleans up any prior Manchester-related records from the database
#   - Resets employee branch assignments for Reid Ryan and Jessica Owens to London
#   - Deletes stale result files before recording timestamp
#   - Launches AttendHRM and logs in, leaving agent at the main dashboard

$logPath = "C:\Users\Docker\task_setup_new_branch_office_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up new_branch_office_setup task ==="

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
    Write-Host "Cleaning up prior Manchester-related records..."

    # 1. Clean attendance entries for target employees on target date
    $cleanup1 = Run-Isql @"
DELETE FROM ATT_REG WHERE REG_EMP_ID IN (108, 120) AND REG_DATE = '2025-03-03';
"@
    Write-Host "Attendance cleanup: $cleanup1"

    # 2. Reset employee branch assignments back to London (101)
    $cleanup2 = Run-Isql @"
UPDATE EMP_EMP SET EMP_BRA_ID = 101 WHERE EMP_ID IN (108, 120);
"@
    Write-Host "Employee branch reset: $cleanup2"

    # 3. Clean leave policy
    # Note: LEA_POL/LEA_POL_DET may not exist in all DB versions.
    # The leave policy feature stores data in the UI layer; cleanup is best-effort.
    $cleanup3 = Run-Isql @"
DELETE FROM LVE_CFP WHERE EXISTS (SELECT 1 FROM LVE_CFP);
"@
    Write-Host "Leave policy cleanup (best-effort): $cleanup3"

    # 4. Clean week-off pattern details (FK via DPR_ID)
    $cleanup4 = Run-Isql @"
DELETE FROM RST_DDT WHERE DDT_DPR_ID IN
  (SELECT SHP_DPR_ID FROM RST_SHP WHERE UPPER(SHP_NAME) LIKE '%MANCHESTER%WEEKLY%');
"@
    Write-Host "Week-off detail cleanup: $cleanup4"

    # 5. Clean shift and week-off records from RST_SHP
    $cleanup5 = Run-Isql @"
DELETE FROM RST_SHP WHERE UPPER(SHP_NAME) LIKE '%MANCHESTER%';
"@
    Write-Host "Shift/week-off cleanup: $cleanup5"

    # 6. Clean branch
    $cleanup6 = Run-Isql @"
DELETE FROM WGR_BRA WHERE UPPER(BRA_NAME) LIKE '%MANCHESTER%';
"@
    Write-Host "Branch cleanup: $cleanup6"

    # Record setup state
    $state = @{
        branch_name        = "Manchester"
        branch_code        = "MAN"
        shift_name         = "Manchester Standard"
        weekoff_name       = "Manchester Weekly"
        policy_name        = "Manchester Staff Leave 2025"
        transfer_emp_ids   = @(108, 120)
        transfer_emp_names = @("Reid Ryan", "Jessica Owens")
        original_branch_id = 101
        attendance_date    = "2025-03-03"
        seeded_at          = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -Path "C:\temp\new_branch_office_setup_state.json" -Encoding ASCII
    Write-Host "Setup state saved."

    # Delete stale result files BEFORE recording timestamp
    Remove-Item -Path "C:\temp\new_branch_office_result.json" -Force -ErrorAction SilentlyContinue

    (Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Set-Content -Path "C:\temp\task_start_timestamp.txt" -Encoding ASCII

    # ---- Launch AttendHRM ----
    Close-Browsers
    $edgeKiller = Start-EdgeKillerTask

    try {
        Launch-AttendHRMInteractive
        $started = Wait-ForAttendHRM -TimeoutSec 30
        if (-not $started) {
            Write-Host "WARNING: AttendHRM not detected, proceeding anyway"
        }
        Login-AttendHRM -WaitAfterLoginSec 15
        Set-AttendHRMForeground | Out-Null
        Start-Sleep -Seconds 1
        Write-Host "Task ready: AttendHRM logged in, agent at main dashboard."
    } finally {
        Stop-EdgeKillerTask -KillerInfo $edgeKiller
    }

    Write-Host "=== new_branch_office_setup setup complete ==="

} catch {
    Write-Host "ERROR in setup_task.ps1: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
