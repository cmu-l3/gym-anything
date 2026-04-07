# export_result.ps1 — add_employee_qualification
# Checks if MBA in Finance qualification was added for Robert Clarke (EMP-1042).
# Writes result to C:\workspace\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_add_employee_qualification.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting add_employee_qualification Result ==="

    . "C:\workspace\scripts\task_utils.ps1"
    Stop-AttendHRM
    Start-Sleep -Seconds 3

    $isqlPath = "C:\Program Files (x86)\Firebird\Firebird_5_0\isql.exe"
    $dbPath   = "C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB"

    function Get-IsqlScalar {
        param([string]$sql)
        $tmp = "C:\Windows\Temp\isql_exp_$(Get-Random).sql"
        Set-Content -Path $tmp -Value ("SET HEADING OFF;`n" + $sql + "`nEXIT;") -Encoding ASCII
        $out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmp 2>&1
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        $lines = ($out | Out-String) -split '\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        if ($lines.Count -gt 0) { return $lines[-1].Trim() }
        return ''
    }

    function Get-IsqlCount {
        param([string]$sql)
        $tmp = "C:\Windows\Temp\isql_exp_$(Get-Random).sql"
        Set-Content -Path $tmp -Value ("SET HEADING OFF;`n" + $sql + "`nEXIT;") -Encoding ASCII
        $out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmp 2>&1
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        $lines = ($out | Out-String) -split '\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        if ($lines.Count -gt 0) { return [int]$lines[-1] }
        return -1
    }

    $empFilter = "QUA_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1042') AND UPPER(QUA_NAME) LIKE '%MBA%'"

    $qualification = Get-IsqlScalar "SELECT QUA_NAME FROM EMP_QUA WHERE $empFilter;"
    $institution = Get-IsqlScalar "SELECT QUA_INSTITUTION FROM EMP_QUA WHERE $empFilter;"
    $year = Get-IsqlScalar "SELECT QUA_YEAR FROM EMP_QUA WHERE $empFilter;"
    $specialization = Get-IsqlScalar "SELECT QUA_SPECIALIZATION FROM EMP_QUA WHERE $empFilter;"
    $recordCount = Get-IsqlCount "SELECT COUNT(*) FROM EMP_QUA WHERE QUA_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1042');"
    $recordAdded = ($qualification -ne '')

    Write-Host "Qualification: $qualification, Institution: $institution, Year: $year, Spec: $specialization"

    $result = @{
        db_data = @{
            qualification  = $qualification
            institution    = $institution
            year           = $year
            specialization = $specialization
        }
        record_added       = $recordAdded
        final_record_count = $recordCount
        export_timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{db_data=@{qualification=''; institution=''; year=''; specialization=''}; record_added=$false; final_record_count=0; error=$($_.Exception.Message)} |
        ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
