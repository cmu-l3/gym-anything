# export_result.ps1 — configure_document_expiry_alert
# Checks if Passport document with expiry alert was added for Elena Rossi (EMP-2050).
# Writes result to C:\workspace\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_configure_document_expiry_alert.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting configure_document_expiry_alert Result ==="

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

    $empFilter = "DOC_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-2050')"
    $docFilter = "$empFilter AND UPPER(DOC_NUMBER) = 'YT8822119'"

    $recordFound = (Get-IsqlCount "SELECT COUNT(*) FROM EMP_DOC WHERE $docFilter;") -gt 0
    $docNumber = Get-IsqlScalar "SELECT DOC_NUMBER FROM EMP_DOC WHERE $docFilter;"
    $expiryDate = Get-IsqlScalar "SELECT DOC_EXPIRY FROM EMP_DOC WHERE $docFilter;"
    $alertDays = Get-IsqlScalar "SELECT DOC_ALERT_DAYS FROM EMP_DOC WHERE $docFilter;"

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Record found: $recordFound, Doc: $docNumber, Expiry: $expiryDate, Alert: $alertDays days"

    $result = @{
        record_found     = $recordFound
        doc_number       = $docNumber
        expiry_date      = $expiryDate
        alert_days       = $alertDays
        app_running      = $appRunning
        screenshot_path  = ""
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{record_found=$false; doc_number=''; expiry_date=''; alert_days=''; app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
