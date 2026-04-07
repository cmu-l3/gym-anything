# export_result.ps1 — configure_overtime_policy
# Checks if "Manufacturing OT Policy" was created with correct rates.
# Writes result to C:\workspace\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_configure_overtime_policy.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting configure_overtime_policy Result ==="

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
        $lines = ($out | Out-String) -split '\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+' }
        if ($lines.Count -gt 0) { return $lines[-1].Trim() }
        return '-1'
    }

    $polFilter = "UPPER(POL_NAME) LIKE '%MANUFACTURING%OT%POLICY%'"
    $found = (Get-IsqlCount "SELECT COUNT(*) FROM OVT_POL WHERE $polFilter;") -gt 0

    $weekdayRate = Get-IsqlScalar "SELECT POL_WEEKDAY_RATE FROM OVT_POL WHERE $polFilter;"
    $weeklyoffRate = Get-IsqlScalar "SELECT POL_WEEKLYOFF_RATE FROM OVT_POL WHERE $polFilter;"
    $threshold = Get-IsqlScalar "SELECT POL_THRESHOLD FROM OVT_POL WHERE $polFilter;"
    $rounding = Get-IsqlScalar "SELECT POL_ROUNDING FROM OVT_POL WHERE $polFilter;"
    $minOt = Get-IsqlScalar "SELECT POL_MIN_OT FROM OVT_POL WHERE $polFilter;"

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Policy found: $found, Weekday: $weekdayRate, Weeklyoff: $weeklyoffRate, Threshold: $threshold"

    $result = @{
        policy_found = $found
        policy_data  = @{
            OT_RATE_WEEKDAY       = $weekdayRate
            OT_RATE_WEEKLYOFF     = $weeklyoffRate
            OT_THRESHOLD_MINUTES  = $threshold
            ROUNDING_MINUTES      = $rounding
            MIN_OT_MINUTES        = $minOt
        }
        app_running      = $appRunning
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written."
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{policy_found=$false; policy_data=@{}; app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
