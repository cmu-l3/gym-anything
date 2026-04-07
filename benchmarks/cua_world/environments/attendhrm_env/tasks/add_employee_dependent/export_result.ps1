# export_result.ps1 — add_employee_dependent
# Checks if dependent Priya Nair was added for Rajesh Nair (EMP-1024).
# Writes result to $env:TEMP\task_result.json (verifier expects C:\Users\Docker\AppData\Local\Temp\task_result.json)

$logPath = "C:\Users\Docker\task_export_add_employee_dependent.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting add_employee_dependent Result ==="

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

    function Get-IsqlScalar {
        param([string]$sql)
        $raw = Get-IsqlResult $sql
        $lines = $raw -split '\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        if ($lines.Count -gt 0) { return $lines[-1].Trim() }
        return ''
    }

    # Get employee ID for EMP-1024 (Rajesh Nair)
    $empId = Get-IsqlScalar "SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1024';"

    # Check dependent record
    $depName = Get-IsqlScalar "SELECT DEP_NAME FROM EMP_DEP WHERE UPPER(DEP_NAME) LIKE '%PRIYA%NAIR%' AND DEP_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1024');"
    $depRelation = Get-IsqlScalar "SELECT DEP_RELATION FROM EMP_DEP WHERE UPPER(DEP_NAME) LIKE '%PRIYA%NAIR%' AND DEP_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1024');"
    $depDob = Get-IsqlScalar "SELECT DEP_DOB FROM EMP_DEP WHERE UPPER(DEP_NAME) LIKE '%PRIYA%NAIR%' AND DEP_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1024');"

    # Check emergency contact
    $emcName = Get-IsqlScalar "SELECT EMC_NAME FROM EMP_EMC WHERE UPPER(EMC_NAME) LIKE '%PRIYA%NAIR%' AND EMC_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1024');"
    $emcPhone = Get-IsqlScalar "SELECT EMC_PHONE FROM EMP_EMC WHERE UPPER(EMC_NAME) LIKE '%PRIYA%NAIR%' AND EMC_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1024');"
    $emcAddress = Get-IsqlScalar "SELECT EMC_ADDRESS FROM EMP_EMC WHERE UPPER(EMC_NAME) LIKE '%PRIYA%NAIR%' AND EMC_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1024');"

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Dependent: $depName, Relation: $depRelation, DOB: $depDob"
    Write-Host "Emergency: $emcName, Phone: $emcPhone"

    $result = @{
        db_data = @{
            dependent_name     = $depName
            dependent_relation = $depRelation
            dependent_dob      = $depDob
            emergency_name     = $emcName
            emergency_phone    = $emcPhone
            emergency_address  = $emcAddress
        }
        app_running      = $appRunning
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $outPath = "$env:TEMP\task_result.json"
    $result | ConvertTo-Json -Depth 3 | Set-Content -Path $outPath -Encoding UTF8
    Write-Host "Result JSON written to $outPath"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{db_data=@{dependent_name=''; dependent_relation=''; dependent_dob=''; emergency_name=''; emergency_phone=''; emergency_address=''}; app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json -Depth 3 | Set-Content -Path "$env:TEMP\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
