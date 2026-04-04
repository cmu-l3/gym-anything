# Post-task export script for document_anesthetic_summary.
# Collects verification artifacts from the expected output files
# and writes a structured JSON result.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_document_anesthetic_summary.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting document_anesthetic_summary results ==="

    $desktop = "C:\Users\Docker\Desktop"
    $csvPath = "$desktop\case_0002_vitals.csv"
    $summaryPath = "$desktop\anesthetic_summary_0002.txt"
    $resultPath = "C:\Users\Docker\task_result_summary.json"

    # ---------------------------------------------------------------
    # Initialize result object
    # ---------------------------------------------------------------
    $result = @{
        csv_exists        = $false
        csv_size_bytes    = 0
        csv_header        = ""
        csv_line_count    = 0
        summary_exists    = $false
        summary_size_bytes = 0
        summary_content   = ""
        errors            = @()
    }

    # ---------------------------------------------------------------
    # Check CSV export
    # ---------------------------------------------------------------
    if (Test-Path $csvPath) {
        try {
            $csvInfo = Get-Item $csvPath
            $result.csv_exists = $true
            $result.csv_size_bytes = $csvInfo.Length
            Write-Host "CSV found: $($csvInfo.Length) bytes"

            # Read first line (header)
            $lines = Get-Content $csvPath -TotalCount 2
            if ($lines -and $lines.Count -gt 0) {
                $result.csv_header = $lines[0]
                Write-Host "CSV header: $($lines[0])"
            }

            # Count total lines
            $lineCount = 0
            $reader = [System.IO.StreamReader]::new($csvPath)
            try {
                while ($null -ne $reader.ReadLine()) { $lineCount++ }
            } finally {
                $reader.Close()
            }
            $result.csv_line_count = $lineCount
            Write-Host "CSV total lines: $lineCount"
        } catch {
            $errMsg = "Error reading CSV: $($_.Exception.Message)"
            Write-Host "WARNING: $errMsg"
            $result.errors += $errMsg
        }
    } else {
        Write-Host "WARNING: CSV not found at $csvPath"
        $result.errors += "CSV not found"
    }

    # ---------------------------------------------------------------
    # Check summary document
    # ---------------------------------------------------------------
    if (Test-Path $summaryPath) {
        try {
            $summaryInfo = Get-Item $summaryPath
            $result.summary_exists = $true
            $result.summary_size_bytes = $summaryInfo.Length
            Write-Host "Summary found: $($summaryInfo.Length) bytes"

            # Read the full content (capped at 10KB to avoid huge JSON)
            $rawContent = Get-Content $summaryPath -Raw -ErrorAction SilentlyContinue
            if ($rawContent) {
                if ($rawContent.Length -gt 10240) {
                    $result.summary_content = $rawContent.Substring(0, 10240)
                    Write-Host "Summary content truncated to 10KB"
                } else {
                    $result.summary_content = $rawContent
                }
                Write-Host "Summary content length: $($rawContent.Length) chars"
            }
        } catch {
            $errMsg = "Error reading summary: $($_.Exception.Message)"
            Write-Host "WARNING: $errMsg"
            $result.errors += $errMsg
        }
    } else {
        Write-Host "WARNING: Summary not found at $summaryPath"
        $result.errors += "Summary file not found"
    }

    # ---------------------------------------------------------------
    # Write result JSON
    # ---------------------------------------------------------------
    $result | ConvertTo-Json -Depth 4 | Out-File -FilePath $resultPath -Encoding UTF8 -Force
    Write-Host "Result JSON written to: $resultPath"

    Write-Host "=== document_anesthetic_summary export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
