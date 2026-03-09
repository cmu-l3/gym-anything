# Post-task export script for volatile_anesthetic_case_inventory.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_sevo_inventory.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Exporting volatile_anesthetic_case_inventory results ==="

    $desktop     = "C:\Users\Docker\Desktop"
    $csv0001Path = "$desktop\case_0001_sevo.csv"
    $csv0003Path = "$desktop\case_0003_sevo.csv"
    $reportPath  = "$desktop\anesthetic_inventory.txt"
    $resultPath  = "C:\Users\Docker\task_result_sevo_inventory.json"

    $result = @{
        csv_0001_exists     = $false
        csv_0001_size_bytes = 0
        csv_0001_header     = ""
        csv_0001_line_count = 0
        csv_0003_exists     = $false
        csv_0003_size_bytes = 0
        csv_0003_header     = ""
        csv_0003_line_count = 0
        report_exists       = $false
        report_size_bytes   = 0
        report_content      = ""
        errors              = @()
    }

    # Helper to collect CSV info
    function Get-CsvInfo {
        param([string]$Path, [hashtable]$Out, [string]$Key)
        if (Test-Path $Path) {
            try {
                $info = Get-Item $Path
                $Out["${Key}_exists"]     = $true
                $Out["${Key}_size_bytes"] = $info.Length
                $lines = Get-Content $Path -TotalCount 2
                if ($lines -and $lines.Count -gt 0) { $Out["${Key}_header"] = $lines[0] }
                $lc = 0
                $rdr = [System.IO.StreamReader]::new($Path)
                try { while ($null -ne $rdr.ReadLine()) { $lc++ } } finally { $rdr.Close() }
                $Out["${Key}_line_count"] = $lc
                Write-Host "${Key}: $($info.Length) bytes, $lc lines"
            } catch {
                $Out["errors"] += "${Key} read error: $($_.Exception.Message)"
            }
        } else {
            Write-Host "WARNING: Not found: $Path"
            $Out["errors"] += "${Key} not found: $Path"
        }
    }

    Get-CsvInfo -Path $csv0001Path -Out $result -Key "csv_0001"
    Get-CsvInfo -Path $csv0003Path -Out $result -Key "csv_0003"

    # Report
    if (Test-Path $reportPath) {
        try {
            $info = Get-Item $reportPath
            $result.report_exists     = $true
            $result.report_size_bytes = $info.Length
            $raw = Get-Content $reportPath -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $result.report_content = if ($raw.Length -gt 12000) { $raw.Substring(0, 12000) } else { $raw }
            }
            Write-Host "Report: $($info.Length) bytes"
        } catch {
            $result.errors += "Report read error: $($_.Exception.Message)"
        }
    } else {
        $result.errors += "Report not found: $reportPath"
        Write-Host "WARNING: Report not found"
    }

    $result | ConvertTo-Json -Depth 4 | Out-File $resultPath -Encoding UTF8 -Force
    Write-Host "Result JSON written to: $resultPath"

    Write-Host "=== volatile_anesthetic_case_inventory export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
