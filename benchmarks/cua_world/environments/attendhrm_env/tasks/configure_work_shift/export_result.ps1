# export_result.ps1 — configure_work_shift
# Checks if "Night Shift" (22:00 to 06:00) was created.
# Writes result to C:\workspace\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_configure_work_shift.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting configure_work_shift Result ==="

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

    $recordCount = Get-IsqlCount "SELECT COUNT(*) FROM SHI_SHI WHERE UPPER(SHI_NAME) LIKE '%NIGHT%SHIFT%';"
    $db_modified = ($recordCount -gt 0)

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Night Shift found: $db_modified"

    $result = @{
        db_modified_during_task = $db_modified
        app_was_running         = $appRunning
        export_timestamp        = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{db_modified_during_task=$false; app_was_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
