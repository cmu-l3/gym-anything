# export_result.ps1 — configure_attendance_device
# Checks if device WS-FP-RECEPTION-01 was registered.
# Writes result to C:\workspace\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_configure_attendance_device.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting configure_attendance_device Result ==="

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

    $devFilter = "UPPER(DEV_NAME) LIKE '%WS-FP-RECEPTION-01%'"
    $found = (Get-IsqlCount "SELECT COUNT(*) FROM ATT_DEV WHERE $devFilter;") -gt 0
    $ipAddr = Get-IsqlScalar "SELECT DEV_IP FROM ATT_DEV WHERE $devFilter;"
    $port = Get-IsqlScalar "SELECT DEV_PORT FROM ATT_DEV WHERE $devFilter;"
    $serial = Get-IsqlScalar "SELECT DEV_SERIAL FROM ATT_DEV WHERE $devFilter;"
    $branchName = Get-IsqlScalar "SELECT B.BRA_NAME FROM ATT_DEV D JOIN WGR_BRA B ON D.DEV_BRA_ID = B.BRA_ID WHERE $devFilter;"
    $isActive = Get-IsqlScalar "SELECT DEV_ACTIVE FROM ATT_DEV WHERE $devFilter;"

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Device found: $found, IP: $ipAddr, Port: $port, Serial: $serial, Branch: $branchName"

    $result = @{
        device_data = @{
            found         = $found
            ip_address    = $ipAddr
            port          = $port
            serial_number = $serial
            branch_name   = $branchName
            is_active     = $isActive
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
    @{device_data=@{found=$false}; app_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json -Depth 3 | Set-Content -Path "C:\workspace\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
