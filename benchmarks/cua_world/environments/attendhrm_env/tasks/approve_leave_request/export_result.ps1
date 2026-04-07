# export_result.ps1 — approve_leave_request
# Checks leave request statuses for Anita Roy and Rajiv Menon.
# Writes result to C:\temp\task_result.json (verifier.py reads from here)

$logPath = "C:\Users\Docker\task_export_approve_leave_request.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting approve_leave_request Result ==="

    . "C:\workspace\scripts\task_utils.ps1"
    Stop-AttendHRM
    Start-Sleep -Seconds 3

    New-Item -ItemType Directory -Force -Path "C:\temp" | Out-Null

    $isqlPath = "C:\Program Files (x86)\Firebird\Firebird_5_0\isql.exe"
    $dbPath   = "C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB"

    function Get-IsqlScalar {
        param([string]$sql)
        $tmp = "C:\Windows\Temp\isql_exp_$(Get-Random).sql"
        Set-Content -Path $tmp -Value ("SET HEADING OFF;`n" + $sql + "`nEXIT;") -Encoding ASCII
        $out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmp 2>&1
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        $lines = ($out | Out-String) -split '\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
        if ($lines.Count -gt 0) { return $lines[-1].Trim() }
        return '-1'
    }

    # Status codes: 1=Applied(Pending), 2=Sanctioned(Approved), 3=Rejected
    $anitaStatus = Get-IsqlScalar "SELECT LEA_STATUS FROM LEA_APP WHERE LEA_DATE = '2025-10-15' AND LEA_EMP_ID IN (SELECT EMP_ID FROM EMP_EMP WHERE UPPER(EMP_NAME) LIKE '%ANITA%ROY%');"
    $rajivStatus = Get-IsqlScalar "SELECT LEA_STATUS FROM LEA_APP WHERE LEA_DATE = '2025-10-20' AND LEA_EMP_ID IN (SELECT EMP_ID FROM EMP_EMP WHERE UPPER(EMP_NAME) LIKE '%RAJIV%MENON%');"

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Anita status: $anitaStatus, Rajiv status: $rajivStatus"

    $result = @{
        anita_status     = $anitaStatus
        rajiv_status     = $rajivStatus
        app_was_running  = $appRunning
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\temp\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written to C:\temp\task_result.json"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{anita_status='-1'; rajiv_status='-1'; app_was_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "C:\temp\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
