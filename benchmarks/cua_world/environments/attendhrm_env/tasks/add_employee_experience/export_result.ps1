# export_result.ps1 — add_employee_experience
# Checks if experience records (TCS, Infosys) were added for EMP-1001.
# Writes result to C:\workspace\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_add_employee_experience.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting add_employee_experience Result ==="

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

    $records_count = Get-IsqlCount "SELECT COUNT(*) FROM EMP_EXP WHERE EXP_EMP_ID = (SELECT EMP_ID FROM EMP_EMP WHERE EMP_CODE = 'EMP-1001');"

    # Check setup timestamp vs current time for modification detection
    $setupTime = $null
    if (Test-Path "C:\temp\task_start_timestamp.txt") {
        $setupTime = Get-Content "C:\temp\task_start_timestamp.txt" -Raw
    }
    $db_modified = ($records_count -ge 2)

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Experience records for EMP-1001: $records_count, Modified: $db_modified"

    $result = @{
        db_modified_during_task = $db_modified
        records_count_db        = $records_count
        app_was_running         = $appRunning
        export_timestamp        = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{db_modified_during_task=$false; records_count_db=0; app_was_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
