# export_result.ps1 — manual_attendance_entry
# Checks if manual attendance was recorded for Robert Johnson (EMP003) on Jan 15, 2025.
# Writes result to $env:TEMP\task_result.json (verifier expects C:\Users\Docker\AppData\Local\Temp\task_result.json)

$logPath = "C:\Users\Docker\task_export_manual_attendance_entry.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting manual_attendance_entry Result ==="

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

    $empFilter = "PUN_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP003') AND PUN_DATE = '2025-01-15'"

    $recordExists = (Get-IsqlCount "SELECT COUNT(*) FROM ATT_PUN WHERE $empFilter;") -gt 0
    $inTime = Get-IsqlScalar "SELECT PUN_IN_TIME FROM ATT_PUN WHERE $empFilter;"
    $outTime = Get-IsqlScalar "SELECT PUN_OUT_TIME FROM ATT_PUN WHERE $empFilter;"

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Record exists: $recordExists, In: $inTime, Out: $outTime"

    $result = @{
        db_record_exists  = $recordExists
        retrieved_in_time  = $inTime
        retrieved_out_time = $outTime
        app_running        = $appRunning
        export_timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $outPath = "$env:TEMP\task_result.json"
    $result | ConvertTo-Json -Depth 3 | Set-Content -Path $outPath -Encoding UTF8
    Write-Host "Result JSON written to $outPath"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{db_record_exists=$false; retrieved_in_time=''; retrieved_out_time=''; app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "$env:TEMP\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
