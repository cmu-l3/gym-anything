# export_result.ps1 — update_employee_visa_details
# Checks if visa details were added for Maria Gonzalez.
# Writes result to C:\workspace\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_update_employee_visa_details.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting update_employee_visa_details Result ==="

    . "C:\workspace\scripts\task_utils.ps1"
    Stop-AttendHRM
    Start-Sleep -Seconds 3

    $isqlPath = "C:\Program Files (x86)\Firebird\Firebird_5_0\isql.exe"
    $dbPath   = "C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB"

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

    $empFilter = "(SELECT EMP_ID FROM EMP_EMP WHERE UPPER(EMP_NAME) LIKE '%MARIA%GONZALEZ%')"

    $visaCount = Get-IsqlCount "SELECT COUNT(*) FROM EMP_VIS WHERE UPPER(VIS_NUMBER) = 'V987654321' AND VIS_EMP_ID = $empFilter;"
    $docCount = Get-IsqlCount "SELECT COUNT(*) FROM EMP_DOC WHERE UPPER(DOC_TITLE) LIKE '%RENEWED%WORK%VISA%' AND DOC_EMP_ID = $empFilter;"

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Visa records: $visaCount, Doc records: $docCount"

    $result = @{
        visa_record_count = $visaCount
        doc_record_count  = $docCount
        app_was_running   = $appRunning
        export_timestamp  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{visa_record_count=0; doc_record_count=0; app_was_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
