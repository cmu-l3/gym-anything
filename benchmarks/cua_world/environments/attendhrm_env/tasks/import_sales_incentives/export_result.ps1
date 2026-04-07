# export_result.ps1 — import_sales_incentives
# Checks if sales commission data was imported for 5 employees.
# Writes result to C:\result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_import_sales_incentives.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting import_sales_incentives Result ==="

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

    $employees = @('EMP-SALES-001', 'EMP-SALES-002', 'EMP-SALES-003', 'EMP-SALES-004', 'EMP-SALES-005')
    $records = @{}

    foreach ($emp in $employees) {
        $amount = Get-IsqlScalar "SELECT SDT_AMOUNT FROM SAL_DET WHERE UPPER(SDT_PAY_HEAD) LIKE '%SALES%COMMISSION%' AND SDT_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = '$emp');"
        if ($amount -ne '') {
            $records[$emp] = [double]$amount
        }
    }

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Records found: $($records.Count)"
    foreach ($k in $records.Keys) { Write-Host "  $k = $($records[$k])" }

    $result = @{
        records_found    = $records
        app_running      = $appRunning
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\result.json" -Encoding UTF8
    Write-Host "Result JSON written to C:\result.json"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{records_found=@{}; app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json -Depth 3 | Set-Content -Path "C:\result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
