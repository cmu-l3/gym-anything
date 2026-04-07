# export_result.ps1 — configure_leave_policy
# Checks if "Grade A - Annual Leave Policy 2025" was created.
# Writes result to C:\workspace\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_configure_leave_policy.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting configure_leave_policy Result ==="

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

    function Get-IsqlCount {
        param([string]$sql)
        $raw = Get-IsqlResult $sql
        $lines = $raw -split '\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        if ($lines.Count -gt 0) { return [int]$lines[-1] }
        return -1
    }

    $policyCount = Get-IsqlCount "SELECT COUNT(*) FROM LEA_POL WHERE UPPER(POL_NAME) LIKE '%GRADE A%ANNUAL%LEAVE%POLICY%2025%';"
    $db_modified = ($policyCount -gt 0)

    # Get full SQL output for the verifier
    $sqlOutput = Get-IsqlResult "SELECT POL_NAME, POL_ID FROM LEA_POL WHERE UPPER(POL_NAME) LIKE '%GRADE%A%';"

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Policy found: $db_modified, Count: $policyCount"

    $result = @{
        db_state = @{
            modified_during_task = $db_modified
        }
        sql_output       = $sqlOutput
        app_running      = $appRunning
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{db_state=@{modified_during_task=$false}; sql_output=''; app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
