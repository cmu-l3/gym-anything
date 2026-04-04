# Post-task export script for arterial_pressure_case_audit
# Collects the CSV export and audit report produced by the agent,
# then writes a structured JSON for the verifier.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_art_audit.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting arterial_pressure_case_audit results ==="

    $desktop    = "C:\Users\Docker\Desktop"
    $csvPath    = "$desktop\art_case_export.csv"
    $reportPath = "$desktop\art_audit_report.txt"
    $resultPath = "C:\Users\Docker\task_result_art_audit.json"

    $result = @{
        csv_exists        = $false
        csv_size_bytes    = 0
        csv_header        = ""
        csv_line_count    = 0
        csv_has_art       = $false
        report_exists     = $false
        report_size_bytes = 0
        report_content    = ""
        errors            = @()
    }

    # ---- Collect CSV export ----
    if (Test-Path $csvPath) {
        try {
            $info = Get-Item $csvPath
            $result.csv_exists     = $true
            $result.csv_size_bytes = $info.Length
            Write-Host "CSV found: $($info.Length) bytes"

            $lines = Get-Content $csvPath -TotalCount 2
            if ($lines -and $lines.Count -gt 0) {
                $result.csv_header  = $lines[0]
                $result.csv_has_art = ($lines[0] -match "(?i)\bART\b")
                Write-Host "CSV header: $($lines[0])"
                Write-Host "CSV has ART column: $($result.csv_has_art)"
            }

            $lc = 0
            $reader = [System.IO.StreamReader]::new($csvPath)
            try { while ($null -ne $reader.ReadLine()) { $lc++ } } finally { $reader.Close() }
            $result.csv_line_count = $lc
            Write-Host "CSV line count: $lc"
        } catch {
            $errMsg = "Error reading CSV: $($_.Exception.Message)"
            Write-Host "WARNING: $errMsg"
            $result.errors += $errMsg
        }
    } else {
        Write-Host "WARNING: CSV not found at $csvPath"
        $result.errors += "CSV not found at expected path"
    }

    # ---- Collect audit report ----
    if (Test-Path $reportPath) {
        try {
            $info = Get-Item $reportPath
            $result.report_exists     = $true
            $result.report_size_bytes = $info.Length
            Write-Host "Report found: $($info.Length) bytes"

            $raw = Get-Content $reportPath -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $result.report_content = if ($raw.Length -gt 12000) { $raw.Substring(0, 12000) } else { $raw }
                Write-Host "Report content length: $($raw.Length) chars"
            }
        } catch {
            $errMsg = "Error reading report: $($_.Exception.Message)"
            Write-Host "WARNING: $errMsg"
            $result.errors += $errMsg
        }
    } else {
        Write-Host "WARNING: Report not found at $reportPath"
        $result.errors += "Audit report not found"
    }

    # ---- Write result JSON ----
    $result | ConvertTo-Json -Depth 4 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result JSON written to: $resultPath"

    Write-Host "=== arterial_pressure_case_audit export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
