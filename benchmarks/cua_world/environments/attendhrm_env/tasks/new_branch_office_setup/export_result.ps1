# export_result.ps1 -- new_branch_office_setup
# Queries database for all expected changes from the branch office setup task.
# Checks: branch, shift, week-off, leave policy, employee transfers, attendance.
# Writes result to C:\temp\new_branch_office_result.json

$logPath = "C:\Users\Docker\task_export_new_branch_office_setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting new_branch_office_setup Result ==="

    . "C:\workspace\scripts\task_utils.ps1"
    Stop-AttendHRM
    Start-Sleep -Seconds 3

    $isqlPath = "C:\Program Files (x86)\Firebird\Firebird_5_0\isql.exe"
    $dbPath   = "C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB"

    function Get-IsqlResult {
        param([string]$sql)
        $tmp = "C:\Windows\Temp\isql_exp_$(Get-Random).sql"
        Set-Content -Path $tmp -Value ("SET HEADING OFF;`n" + $sql + "`nEXIT;") -Encoding ASCII
        $out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmp 2>&1
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return ($out | Out-String).Trim()
    }

    function Get-IsqlCount {
        param([string]$sql)
        $raw = Get-IsqlResult $sql
        if ($raw -match 'Statement failed') { return -1 }
        $lines = @($raw -split '\n' | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+$' })
        if ($lines.Count -gt 0) { return [int]$lines[-1] }
        return -1
    }

    function Get-IsqlScalar {
        param([string]$sql)
        $raw = Get-IsqlResult $sql
        if ($raw -match 'Statement failed') { return '' }
        $lines = @($raw -split '\n' | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ne '' })
        if ($lines.Count -gt 0) { return "$($lines[-1])".Trim() }
        return ''
    }

    # === 1. Branch Check ===
    $branchCount = Get-IsqlCount "SELECT COUNT(*) FROM WGR_BRA WHERE UPPER(BRA_NAME) LIKE '%MANCHESTER%';"
    $branchFound = ($branchCount -gt 0)
    $branchCode = Get-IsqlScalar "SELECT BRA_CODE FROM WGR_BRA WHERE UPPER(BRA_NAME) LIKE '%MANCHESTER%';"
    $branchId = Get-IsqlScalar "SELECT BRA_ID FROM WGR_BRA WHERE UPPER(BRA_NAME) LIKE '%MANCHESTER%';"
    Write-Host "Branch: found=$branchFound, code=$branchCode, id=$branchId"

    # === 2. Work Shift Check ===
    $shiftCount = Get-IsqlCount "SELECT COUNT(*) FROM RST_SHP WHERE UPPER(SHP_NAME) LIKE '%MANCHESTER%STANDARD%';"
    $shiftFound = ($shiftCount -gt 0)
    Write-Host "Shift: found=$shiftFound"

    # === 3. Week-Off Pattern Check ===
    $weekoffCount = Get-IsqlCount "SELECT COUNT(*) FROM RST_SHP WHERE UPPER(SHP_NAME) LIKE '%MANCHESTER%WEEKLY%';"
    $weekoffFound = ($weekoffCount -gt 0)
    Write-Host "Week-off: found=$weekoffFound"

    # === 4. Leave Policy Check ===
    # LEA_POL/LEA_POL_DET tables may not exist in all DB versions.
    # Leave policy verification relies primarily on VLM (screenshot) checks.
    $policyFound = $false
    $entitlementCount = -1
    $policyCount = Get-IsqlCount "SELECT COUNT(*) FROM LEA_POL WHERE UPPER(POL_NAME) LIKE '%MANCHESTER%STAFF%LEAVE%2025%';"
    if ($policyCount -gt 0) {
        $policyFound = $true
        $entitlementCount = Get-IsqlCount "SELECT COUNT(*) FROM LEA_POL_DET WHERE POD_POL_ID IN (SELECT POL_ID FROM LEA_POL WHERE UPPER(POL_NAME) LIKE '%MANCHESTER%STAFF%LEAVE%2025%');"
    }
    Write-Host "Leave policy: found=$policyFound, entitlements=$entitlementCount"

    # === 5. Employee Transfer Check ===
    $emp108BranchId = Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 108;"
    $emp120BranchId = Get-IsqlScalar "SELECT EMP_BRA_ID FROM EMP_EMP WHERE EMP_ID = 120;"
    $emp108Transferred = ($emp108BranchId -ne "101")
    $emp120Transferred = ($emp120BranchId -ne "101")
    $emp108AtManchester = $false
    $emp120AtManchester = $false
    if ($branchId -ne '') {
        $emp108AtManchester = ($emp108BranchId -eq $branchId)
        $emp120AtManchester = ($emp120BranchId -eq $branchId)
    }
    Write-Host "Emp 108: branch=$emp108BranchId, transferred=$emp108Transferred, atManchester=$emp108AtManchester"
    Write-Host "Emp 120: branch=$emp120BranchId, transferred=$emp120Transferred, atManchester=$emp120AtManchester"

    # === 6. Attendance Check ===
    $att108Exists = (Get-IsqlCount "SELECT COUNT(*) FROM ATT_REG WHERE REG_EMP_ID = 108 AND REG_DATE = '2025-03-03';") -gt 0
    $att108In = Get-IsqlScalar "SELECT REG_BGN FROM ATT_REG WHERE REG_EMP_ID = 108 AND REG_DATE = '2025-03-03';"
    $att108Out = Get-IsqlScalar "SELECT REG_END FROM ATT_REG WHERE REG_EMP_ID = 108 AND REG_DATE = '2025-03-03';"

    $att120Exists = (Get-IsqlCount "SELECT COUNT(*) FROM ATT_REG WHERE REG_EMP_ID = 120 AND REG_DATE = '2025-03-03';") -gt 0
    $att120In = Get-IsqlScalar "SELECT REG_BGN FROM ATT_REG WHERE REG_EMP_ID = 120 AND REG_DATE = '2025-03-03';"
    $att120Out = Get-IsqlScalar "SELECT REG_END FROM ATT_REG WHERE REG_EMP_ID = 120 AND REG_DATE = '2025-03-03';"

    Write-Host "Att 108: exists=$att108Exists, in=$att108In, out=$att108Out"
    Write-Host "Att 120: exists=$att120Exists, in=$att120In, out=$att120Out"

    # === Build Result ===
    $result = @{
        branch_found          = $branchFound
        branch_code           = $branchCode
        branch_id             = $branchId
        shift_found           = $shiftFound
        weekoff_found         = $weekoffFound
        policy_found          = $policyFound
        policy_entitlements   = $entitlementCount
        emp_108_branch_id     = $emp108BranchId
        emp_120_branch_id     = $emp120BranchId
        emp_108_transferred   = $emp108Transferred
        emp_120_transferred   = $emp120Transferred
        emp_108_at_manchester = $emp108AtManchester
        emp_120_at_manchester = $emp120AtManchester
        att_108_exists        = $att108Exists
        att_108_in            = $att108In
        att_108_out           = $att108Out
        att_120_exists        = $att120Exists
        att_120_in            = $att120In
        att_120_out           = $att120Out
        export_timestamp      = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $jsonText = $result | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText("C:\temp\new_branch_office_result.json", $jsonText, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Result JSON written to C:\temp\new_branch_office_result.json"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{
        branch_found=$false; shift_found=$false; weekoff_found=$false
        policy_found=$false; emp_108_transferred=$false; emp_120_transferred=$false
        att_108_exists=$false; att_120_exists=$false
        error="$($_.Exception.Message)"
    } | ConvertTo-Json | ForEach-Object { [System.IO.File]::WriteAllText("C:\temp\new_branch_office_result.json", $_, (New-Object System.Text.UTF8Encoding $false)) }
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
