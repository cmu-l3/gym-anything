# export_result.ps1 — configure_attendance_rounding
# Checks attendance rounding settings.
# Writes result to C:\tmp\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_configure_attendance_rounding.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting configure_attendance_rounding Result ==="

    . "C:\workspace\scripts\task_utils.ps1"
    Stop-AttendHRM
    Start-Sleep -Seconds 3

    New-Item -ItemType Directory -Force -Path "C:\tmp" | Out-Null

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

    # Query rounding settings from the settings table
    $roundingInMethod = Get-IsqlScalar "SELECT SET_VALUE FROM SYS_SET WHERE UPPER(SET_KEY) LIKE '%ROUNDING%IN%METHOD%';"
    $roundingInValue = Get-IsqlScalar "SELECT SET_VALUE FROM SYS_SET WHERE UPPER(SET_KEY) LIKE '%ROUNDING%IN%VALUE%';"
    $roundingOutMethod = Get-IsqlScalar "SELECT SET_VALUE FROM SYS_SET WHERE UPPER(SET_KEY) LIKE '%ROUNDING%OUT%METHOD%';"
    $roundingOutValue = Get-IsqlScalar "SELECT SET_VALUE FROM SYS_SET WHERE UPPER(SET_KEY) LIKE '%ROUNDING%OUT%VALUE%';"

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "In: method=$roundingInMethod value=$roundingInValue, Out: method=$roundingOutMethod value=$roundingOutValue"

    $result = @{
        db_connected       = $true
        rounding_in_method  = $roundingInMethod
        rounding_in_value   = $roundingInValue
        rounding_out_method = $roundingOutMethod
        rounding_out_value  = $roundingOutValue
        app_running         = $appRunning
        export_timestamp    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\tmp\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written to C:\tmp\task_result.json"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{db_connected=$false; rounding_in_method=''; rounding_in_value=''; rounding_out_method=''; rounding_out_value=''; app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "C:\tmp\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
