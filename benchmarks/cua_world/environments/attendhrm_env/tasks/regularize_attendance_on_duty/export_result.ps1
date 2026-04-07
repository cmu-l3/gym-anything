# export_result.ps1 — regularize_attendance_on_duty
# Checks if attendance for Anita Desai (EMP-2055) was changed to "On Duty" for Feb 10-12, 2025.
# Writes result to C:\Temp\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_regularize_attendance_on_duty.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting regularize_attendance_on_duty Result ==="

    . "C:\workspace\scripts\task_utils.ps1"
    Stop-AttendHRM
    Start-Sleep -Seconds 3

    New-Item -ItemType Directory -Force -Path "C:\Temp" | Out-Null

    $isqlPath = "C:\Program Files (x86)\Firebird\Firebird_5_0\isql.exe"
    $dbPath   = "C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB"

    function Get-IsqlResult {
        param([string]$sql)
        $tmp = "C:\Windows\Temp\isql_exp_$(Get-Random).sql"
        Set-Content -Path $tmp -Value ("SET HEADING OFF;`nSET LIST ON;`n" + $sql + "`nEXIT;") -Encoding ASCII
        $out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmp 2>&1
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return ($out | Out-String).Trim()
    }

    # Query attendance records for EMP-2055 on Feb 10-12
    $dates = @('2025-02-10', '2025-02-11', '2025-02-12')
    $dbRecords = @()

    foreach ($date in $dates) {
        $status = ''
        $remarks = ''
        $rawResult = Get-IsqlResult "SELECT REG_STATUS, REG_REMARKS FROM ATT_REG WHERE REG_DATE = '$date' AND REG_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-2055');"

        if ($rawResult -ne '') {
            $lines = $rawResult -split '\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            foreach ($line in $lines) {
                if ($line -match 'REG_STATUS\s+(.+)') { $status = $matches[1].Trim() }
                if ($line -match 'REG_REMARKS\s+(.+)') { $remarks = $matches[1].Trim() }
            }
        }

        $dbRecords += @{
            date    = $date
            status  = $status
            remarks = $remarks
        }
    }

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Records:"
    foreach ($r in $dbRecords) { Write-Host "  $($r.date): status=$($r.status), remarks=$($r.remarks)" }

    $result = @{
        db_records       = $dbRecords
        app_running      = $appRunning
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 5 | Set-Content -Path "C:\Temp\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written to C:\Temp\task_result.json"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{db_records=@(); app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json -Depth 3 | Set-Content -Path "C:\Temp\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
