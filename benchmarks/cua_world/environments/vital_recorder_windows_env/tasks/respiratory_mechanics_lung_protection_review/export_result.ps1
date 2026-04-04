# Post-task export script for respiratory_mechanics_lung_protection_review.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_resp_mechanics.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { Write-Host "WARNING: Start-Transcript failed" }

try {
    Write-Host "=== Exporting respiratory_mechanics_lung_protection_review results ==="

    $desktop    = "C:\Users\Docker\Desktop"
    $csvPath    = "$desktop\lung_protection_intraop.csv"
    $reportPath = "$desktop\ventilation_review.txt"
    $resultPath = "C:\Users\Docker\task_result_resp_mechanics.json"

    $result = @{
        csv_exists        = $false
        csv_size_bytes    = 0
        csv_header        = ""
        csv_line_count    = 0
        report_exists     = $false
        report_size_bytes = 0
        report_content    = ""
        errors            = @()
    }

    if (Test-Path $csvPath) {
        try {
            $info = Get-Item $csvPath
            $result.csv_exists     = $true
            $result.csv_size_bytes = $info.Length

            $lines = Get-Content $csvPath -TotalCount 2
            if ($lines -and $lines.Count -gt 0) {
                $result.csv_header = $lines[0]
                Write-Host "CSV header: $($lines[0])"
            }

            $lc = 0
            $rdr = [System.IO.StreamReader]::new($csvPath)
            try { while ($null -ne $rdr.ReadLine()) { $lc++ } } finally { $rdr.Close() }
            $result.csv_line_count = $lc
            Write-Host "CSV: $($info.Length) bytes, $lc lines"
        } catch {
            $result.errors += "CSV error: $($_.Exception.Message)"
        }
    } else {
        $result.errors += "CSV not found: $csvPath"
        Write-Host "WARNING: CSV not found"
    }

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
            $result.errors += "Report error: $($_.Exception.Message)"
        }
    } else {
        $result.errors += "Report not found: $reportPath"
        Write-Host "WARNING: Report not found"
    }

    $result | ConvertTo-Json -Depth 4 | Out-File $resultPath -Encoding UTF8 -Force
    Write-Host "Result JSON: $resultPath"

    Write-Host "=== respiratory_mechanics_lung_protection_review export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
