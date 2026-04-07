# export_result.ps1 — add_branch
# Checks if the Downtown Office branch was created in the database.
# Writes result to C:\tmp\task_result.json (path expected by verifier.py)

$logPath = "C:\Users\Docker\task_export_add_branch.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting add_branch Result ==="

    . "C:\workspace\scripts\task_utils.ps1"
    Stop-AttendHRM
    Start-Sleep -Seconds 3

    New-Item -ItemType Directory -Force -Path "C:\tmp" | Out-Null

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

    function Get-IsqlScalar {
        param([string]$sql)
        $raw = Get-IsqlResult $sql
        $lines = $raw -split '\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        if ($lines.Count -gt 0) { return $lines[-1].Trim() }
        return ''
    }

    # Check if Downtown Office branch exists
    $record_count = Get-IsqlCount "SELECT COUNT(*) FROM WGR_BRA WHERE UPPER(BRA_NAME) LIKE '%DOWNTOWN%OFFICE%';"
    $record_found = ($record_count -gt 0)

    # Check branch code
    $code = Get-IsqlScalar "SELECT BRA_CODE FROM WGR_BRA WHERE UPPER(BRA_NAME) LIKE '%DOWNTOWN%OFFICE%';"
    $code_match = ($code -like '*DTN*')

    # Check city (stored in BRA_CITY or similar column)
    $city = Get-IsqlScalar "SELECT BRA_CITY FROM WGR_BRA WHERE UPPER(BRA_NAME) LIKE '%DOWNTOWN%OFFICE%';"
    $city_match = ($city -like '*San Francisco*' -or $city -like '*SAN FRANCISCO*')

    # Total branch count
    $total_branches = Get-IsqlCount "SELECT COUNT(*) FROM WGR_BRA;"
    $count_increased = ($total_branches -gt 3)

    Write-Host "Record found: $record_found, Code: $code (match=$code_match), City: $city (match=$city_match), Total: $total_branches"

    $result = @{
        record_found    = $record_found
        code_match      = $code_match
        city_match      = $city_match
        count_increased = $count_increased
        branch_code     = $code
        branch_city     = $city
        total_branches  = $total_branches
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }

    $result | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\tmp\task_result.json" -Encoding UTF8
    Write-Host "Result JSON written to C:\tmp\task_result.json"
    Write-Host "=== Export Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    @{record_found=$false; code_match=$false; city_match=$false; count_increased=$false; error=$($_.Exception.Message)} |
        ConvertTo-Json | Set-Content -Path "C:\tmp\task_result.json" -Encoding UTF8
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
