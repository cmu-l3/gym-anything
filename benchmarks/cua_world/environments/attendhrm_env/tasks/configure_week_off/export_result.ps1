# export_result.ps1 — configure_week_off
# Checks if "Manufacturing Wing A" week-off pattern was created.
# Writes result to C:\Windows\Temp\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_configure_week_off.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting configure_week_off Result ==="

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

    $recordCount = Get-IsqlCount "SELECT COUNT(*) FROM WKO_WKO WHERE UPPER(WKO_NAME) LIKE '%MANUFACTURING%WING%A%';"
    $recordFound = ($recordCount -gt 0)
    $db_modified = $recordFound

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Record found: $recordFound"

    $result = @{
        db_modified          = $db_modified
        week_off_record_found = $recordFound
        app_running          = $appRunning
        export_timestamp     = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\Windows\Temp\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{db_modified=$false; week_off_record_found=$false; app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "C:\Windows\Temp\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
