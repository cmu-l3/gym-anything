# export_result.ps1 — q4_compliance_data_fix
# Checks if branch errors were fixed, department swaps corrected, and new hires imported.
# Writes C:\temp\q4_compliance_result.json

$logPath = "C:\Users\Docker\task_export_q4_compliance.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting q4_compliance_data_fix Result ==="

    . "C:\workspace\scripts\task_utils.ps1"
    Stop-AttendHRM
    Start-Sleep -Seconds 3

    New-Item -ItemType Directory -Force -Path "C:\temp" | Out-Null

    $isqlPath = "C:\Program Files (x86)\Firebird\Firebird_5_0\isql.exe"
    $dbPath   = "C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB"

    function Get-IsqlCount {
        param([string]$sql)
        $tmp = "C:\Windows\Temp\isql_exp_$(Get-Random).sql"
        # SET HEADING OFF suppresses column headers so only the numeric value remains
        Set-Content -Path $tmp -Value ("SET HEADING OFF;`n" + $sql + "`nEXIT;") -Encoding ASCII
        $out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmp 2>&1
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        $lines = ($out | Out-String) -split '\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^\d+$' }
        # Use last digit-only line to skip any banner/startup output
        if ($lines.Count -gt 0) { return [int]$lines[-1] }
        return -1
    }

    function Get-IsqlScalar {
        param([string]$sql)
        $tmp = "C:\Windows\Temp\isql_exp_$(Get-Random).sql"
        # SET HEADING OFF suppresses headers; digit-only filter skips trailing "N records fetched"
        Set-Content -Path $tmp -Value ("SET HEADING OFF;`n" + $sql + "`nEXIT;") -Encoding ASCII
        $out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmp 2>&1
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        $lines = ($out | Out-String) -split '\n' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^\d+$' }
        if ($lines.Count -gt 0) { return $lines[-1] }
        return ''
    }

    # ---- Issue 1: Check branch fixes ----
    # Correct: EMP 108->101(London), EMP 120->101(London), EMP 135->102(Norwich), EMP 148->101(London)
    $bra_108 = (Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 108;") -replace '\D', ''
    $bra_120 = (Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 120;") -replace '\D', ''
    $bra_135 = (Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 135;") -replace '\D', ''
    $bra_148 = (Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 148;") -replace '\D', ''

    $emp_108_fixed = ($bra_108 -eq '101')
    $emp_120_fixed = ($bra_120 -eq '101')
    $emp_135_fixed = ($bra_135 -eq '102')
    $emp_148_fixed = ($bra_148 -eq '101')

    $branches_still_invalid = Get-IsqlCount "SELECT COUNT(*) FROM EMP_EMP WHERE EMP_ID IN (108, 120, 135, 148) AND EMP_BRA_ID = 99;"
    Write-Host "EMP 108 BRA_ID: $bra_108 (fixed=$emp_108_fixed)"
    Write-Host "EMP 120 BRA_ID: $bra_120 (fixed=$emp_120_fixed)"
    Write-Host "EMP 135 BRA_ID: $bra_135 (fixed=$emp_135_fixed)"
    Write-Host "EMP 148 BRA_ID: $bra_148 (fixed=$emp_148_fixed)"
    Write-Host "Still invalid (BRA_ID=99): $branches_still_invalid"

    # ---- Issue 2: Check department swap fixes ----
    # Correct: EMP 113 -> 106 (Accounts), EMP 137 -> 102 (IT)
    $afd_113 = (Get-IsqlScalar "SELECT EMP_AFD_ID FROM EMP_EMP WHERE EMP_ID = 113;") -replace '\D', ''
    $afd_137 = (Get-IsqlScalar "SELECT EMP_AFD_ID FROM EMP_EMP WHERE EMP_ID = 137;") -replace '\D', ''

    $emp_113_fixed = ($afd_113 -eq '106')
    $emp_137_fixed = ($afd_137 -eq '102')
    Write-Host "EMP 113 AFD_ID: $afd_113 (fixed=$emp_113_fixed)"
    Write-Host "EMP 137 AFD_ID: $afd_137 (fixed=$emp_137_fixed)"

    # ---- Issue 3: Check new hires imported ----
    $new_hire_count = Get-IsqlCount "SELECT COUNT(*) FROM EMP_EMP WHERE EMP_ID IN (5001, 5002, 5003, 5004, 5005);"
    Write-Host "New hires imported: $new_hire_count"

    # Check each new hire's branch and dept
    $bra_5001 = (Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 5001;") -replace '\D', ''
    $bra_5002 = (Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 5002;") -replace '\D', ''
    $bra_5003 = (Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 5003;") -replace '\D', ''
    $bra_5004 = (Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 5004;") -replace '\D', ''
    $bra_5005 = (Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 5005;") -replace '\D', ''

    $afd_5001 = (Get-IsqlScalar "SELECT EMP_AFD_ID FROM EMP_EMP WHERE EMP_ID = 5001;") -replace '\D', ''
    $afd_5002 = (Get-IsqlScalar "SELECT EMP_AFD_ID FROM EMP_EMP WHERE EMP_ID = 5002;") -replace '\D', ''
    $afd_5003 = (Get-IsqlScalar "SELECT EMP_AFD_ID FROM EMP_EMP WHERE EMP_ID = 5003;") -replace '\D', ''
    $afd_5004 = (Get-IsqlScalar "SELECT EMP_AFD_ID FROM EMP_EMP WHERE EMP_ID = 5004;") -replace '\D', ''
    $afd_5005 = (Get-IsqlScalar "SELECT EMP_AFD_ID FROM EMP_EMP WHERE EMP_ID = 5005;") -replace '\D', ''

    # New hire correct branches: 5001->101(LONDON), 5002->101(LONDON), 5003->102(NORWICH), 5004->102(NORWICH), 5005->103(DUBLIN)
    $nh_correct_branches = Get-IsqlCount @"
SELECT COUNT(*) FROM EMP_EMP WHERE
(EMP_ID = 5001 AND EMP_BRA_ID = 101) OR
(EMP_ID = 5002 AND EMP_BRA_ID = 101) OR
(EMP_ID = 5003 AND EMP_BRA_ID = 102) OR
(EMP_ID = 5004 AND EMP_BRA_ID = 102) OR
(EMP_ID = 5005 AND EMP_BRA_ID = 103);
"@

    # New hire correct depts: 5001->106(Accounts), 5002->104(Marketing), 5003->102(IT), 5004->105(Production), 5005->101(Admin)
    $nh_correct_depts = Get-IsqlCount @"
SELECT COUNT(*) FROM EMP_EMP WHERE
(EMP_ID = 5001 AND EMP_AFD_ID = 106) OR
(EMP_ID = 5002 AND EMP_AFD_ID = 104) OR
(EMP_ID = 5003 AND EMP_AFD_ID = 102) OR
(EMP_ID = 5004 AND EMP_AFD_ID = 105) OR
(EMP_ID = 5005 AND EMP_AFD_ID = 101);
"@
    Write-Host "New hires with correct branch: $nh_correct_branches"
    Write-Host "New hires with correct dept: $nh_correct_depts"

    $result = @{
        emp_108_bra_id              = $bra_108
        emp_120_bra_id              = $bra_120
        emp_135_bra_id              = $bra_135
        emp_148_bra_id              = $bra_148
        emp_108_branch_fixed        = $emp_108_fixed
        emp_120_branch_fixed        = $emp_120_fixed
        emp_135_branch_fixed        = $emp_135_fixed
        emp_148_branch_fixed        = $emp_148_fixed
        branches_still_invalid      = $branches_still_invalid
        emp_113_afd_id              = $afd_113
        emp_137_afd_id              = $afd_137
        emp_113_dept_fixed          = $emp_113_fixed
        emp_137_dept_fixed          = $emp_137_fixed
        new_hires_imported          = $new_hire_count
        new_hires_correct_branch    = $nh_correct_branches
        new_hires_correct_dept      = $nh_correct_depts
        emp_5001_bra = $bra_5001; emp_5002_bra = $bra_5002; emp_5003_bra = $bra_5003
        emp_5004_bra = $bra_5004; emp_5005_bra = $bra_5005
        emp_5001_afd = $afd_5001; emp_5002_afd = $afd_5002; emp_5003_afd = $afd_5003
        emp_5004_afd = $afd_5004; emp_5005_afd = $afd_5005
        export_timestamp            = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\temp\q4_compliance_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR in export_result.ps1: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{error="export_exception"; branches_still_invalid=4; emp_113_dept_fixed=$false; emp_137_dept_fixed=$false; new_hires_imported=0} |
        ConvertTo-Json | Set-Content -Path "C:\temp\q4_compliance_result.json" -Encoding ASCII
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
