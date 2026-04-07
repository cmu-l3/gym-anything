# export_result.ps1 — perform_bulk_salary_revision
# Checks if bulk salary revision was applied to Junior Developers.
# Writes result to C:\workspace\tasks\perform_bulk_salary_revision\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_perform_bulk_salary_revision.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting perform_bulk_salary_revision Result ==="

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

    # Count Junior Developers with salary revision to 3500 on 2025-04-01
    $targetsUpdated = Get-IsqlCount @"
SELECT COUNT(*) FROM SAL_REV WHERE REV_EFFECTIVE_DATE = '2025-04-01'
  AND REV_AMOUNT = 3500
  AND REV_EMP_ID IN (SELECT EMP_ID FROM EMP_EMP WHERE UPPER(EMP_DESIGNATION) LIKE '%JUNIOR%DEVELOPER%');
"@

    # Count non-target employees with salary revision on same date
    $nonTargetsAffected = Get-IsqlCount @"
SELECT COUNT(*) FROM SAL_REV WHERE REV_EFFECTIVE_DATE = '2025-04-01'
  AND REV_EMP_ID NOT IN (SELECT EMP_ID FROM EMP_EMP WHERE UPPER(EMP_DESIGNATION) LIKE '%JUNIOR%DEVELOPER%');
"@

    $appRunning = (Get-Process -Name "Attend" -ErrorAction SilentlyContinue) -ne $null

    Write-Host "Targets updated: $targetsUpdated, Non-targets affected: $nonTargetsAffected"

    $result = @{
        targets_updated_count    = $targetsUpdated
        non_targets_affected_count = $nonTargetsAffected
        app_was_running          = $appRunning
        export_timestamp         = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $outPath = "C:\workspace\tasks\perform_bulk_salary_revision\task_result.json"
    $result | ConvertTo-Json -Depth 3 | Set-Content -Path $outPath -Encoding UTF8
    Write-Host "Result JSON written to $outPath"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{targets_updated_count=0; non_targets_affected_count=0; app_was_running=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "C:\workspace\tasks\perform_bulk_salary_revision\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
