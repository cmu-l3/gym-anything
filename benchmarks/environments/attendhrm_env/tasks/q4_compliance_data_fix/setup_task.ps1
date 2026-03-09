# setup_task.ps1 — q4_compliance_data_fix
# Seeds the database with Q4 compliance issues for the agent to fix.
#
# WHAT IT DOES:
#   - Sets EMP 108 (Reid Ryan), 120 (Jessica Owens), 135 (Daisy Brooks),
#     148 (Jack West) to invalid BRA_ID=99 (non-existent branch)
#   - Swaps departments: EMP 113 (Miller Russell) Accounts->IT,
#     EMP 137 (Ryan Murphy) IT->Accounts
#   - Copies q4_new_hires.csv to Desktop
#   - Launches AttendHRM

$logPath = "C:\Users\Docker\task_setup_q4_compliance.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up q4_compliance_data_fix task ==="

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
    $cleanup = Run-Isql @"
UPDATE EMP_EMP SET EMP_BRA_ID = 101 WHERE EMP_ID IN (108, 120, 148);
UPDATE EMP_EMP SET EMP_BRA_ID = 102 WHERE EMP_ID = 135;
UPDATE EMP_EMP SET EMP_AFD_ID = 106 WHERE EMP_ID = 113;
UPDATE EMP_EMP SET EMP_AFD_ID = 102 WHERE EMP_ID = 137;
DELETE FROM EMP_EMP WHERE EMP_ID IN (5001, 5002, 5003, 5004, 5005);
"@
    Write-Host "Cleanup prior run: $cleanup"

    # ---- Issue 1: Set 4 employees to invalid branch BRA_ID=99 ----
    Write-Host "Seeding invalid branch (BRA_ID=99) for EMP 108, 120, 135, 148..."
    $r1 = Run-Isql @"
UPDATE EMP_EMP SET EMP_BRA_ID = 99
WHERE EMP_ID IN (108, 120, 135, 148);
"@
    Write-Host "Invalid branch seeded: $r1"

    # ---- Issue 2: Swap departments for EMP 113 and 137 ----
    Write-Host "Swapping departments: EMP 113 Accounts->IT, EMP 137 IT->Accounts..."
    $r2 = Run-Isql @"
UPDATE EMP_EMP SET EMP_AFD_ID = 102 WHERE EMP_ID = 113;
UPDATE EMP_EMP SET EMP_AFD_ID = 106 WHERE EMP_ID = 137;
"@
    Write-Host "Department swap seeded: $r2"

    # Record setup state
    $state = @{
        invalid_branch_emp_ids      = @(108, 120, 135, 148)
        invalid_bra_id              = 99
        correct_branches            = @{ "108" = 101; "120" = 101; "135" = 102; "148" = 101 }
        dept_swap_emp_ids           = @(113, 137)
        emp_113_correct_afd         = 106
        emp_137_correct_afd         = 102
        new_hire_emp_ids            = @(5001, 5002, 5003, 5004, 5005)
        seeded_at                   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $state | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\temp\q4_compliance_setup.json" -Encoding ASCII
    Write-Host "Setup state saved."

    # ---- Copy CSV to Desktop ----
    Write-Host "Copying q4_new_hires.csv to Desktop..."
    $srcCsv = "C:\workspace\data\q4_new_hires.csv"
    $dstCsv = "C:\Users\Docker\Desktop\q4_new_hires.csv"
    if (Test-Path $srcCsv) {
        Copy-Item -Path $srcCsv -Destination $dstCsv -Force
        Write-Host "q4_new_hires.csv copied to Desktop."
    } else {
        Write-Host "WARNING: q4_new_hires.csv not found at $srcCsv"
    }

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
        Navigate-ToEmployeeList
        Write-Host "Task ready: 4 employees with invalid branch, 2 with swapped depts, CSV on Desktop."
    } finally {
        Stop-EdgeKillerTask -KillerInfo $edgeKiller
    }

    Write-Host "=== q4_compliance_data_fix setup complete ==="

} catch {
    Write-Host "ERROR in setup_task.ps1: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
