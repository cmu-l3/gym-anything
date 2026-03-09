# Post-task export script for compare_surgical_cases.
# Collects verification artifacts from the three expected output files
# and writes a structured JSON result.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_compare_surgical_cases.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting compare_surgical_cases results ==="

    $desktop = "C:\Users\Docker\Desktop"
    $csv1Path = "$desktop\case_0001_data.csv"
    $csv2Path = "$desktop\case_0002_data.csv"
    $summaryPath = "$desktop\case_comparison.txt"
    $resultPath = "C:\Users\Docker\task_result_compare.json"

    # ---------------------------------------------------------------
    # Initialize result object
    # ---------------------------------------------------------------
    $result = @{
        csv_0001_exists       = $false
        csv_0001_size_bytes   = 0
        csv_0001_header       = ""
        csv_0001_line_count   = 0
        csv_0002_exists       = $false
        csv_0002_size_bytes   = 0
        csv_0002_header       = ""
        csv_0002_line_count   = 0
        summary_exists        = $false
        summary_size_bytes    = 0
        summary_content       = ""
        errors                = @()
    }

    # ---------------------------------------------------------------
    # Check CSV for case 0001
    # ---------------------------------------------------------------
    if (Test-Path $csv1Path) {
        try {
            $csv1Info = Get-Item $csv1Path
            $result.csv_0001_exists = $true
            $result.csv_0001_size_bytes = $csv1Info.Length
            Write-Host "CSV 0001 found: $($csv1Info.Length) bytes"

            # Read first line (header)
            $lines1 = Get-Content $csv1Path -TotalCount 2
            if ($lines1 -and $lines1.Count -gt 0) {
                $result.csv_0001_header = $lines1[0]
                Write-Host "CSV 0001 header: $($lines1[0])"
            }

            # Count total lines
            $lineCount1 = 0
            $reader1 = [System.IO.StreamReader]::new($csv1Path)
            try {
                while ($null -ne $reader1.ReadLine()) { $lineCount1++ }
            } finally {
                $reader1.Close()
            }
            $result.csv_0001_line_count = $lineCount1
            Write-Host "CSV 0001 total lines: $lineCount1"
        } catch {
            $errMsg = "Error reading CSV 0001: $($_.Exception.Message)"
            Write-Host "WARNING: $errMsg"
            $result.errors += $errMsg
        }
    } else {
        Write-Host "WARNING: CSV 0001 not found at $csv1Path"
        $result.errors += "CSV 0001 not found"
    }

    # ---------------------------------------------------------------
    # Check CSV for case 0002
    # ---------------------------------------------------------------
    if (Test-Path $csv2Path) {
        try {
            $csv2Info = Get-Item $csv2Path
            $result.csv_0002_exists = $true
            $result.csv_0002_size_bytes = $csv2Info.Length
            Write-Host "CSV 0002 found: $($csv2Info.Length) bytes"

            # Read first line (header)
            $lines2 = Get-Content $csv2Path -TotalCount 2
            if ($lines2 -and $lines2.Count -gt 0) {
                $result.csv_0002_header = $lines2[0]
                Write-Host "CSV 0002 header: $($lines2[0])"
            }

            # Count total lines
            $lineCount2 = 0
            $reader2 = [System.IO.StreamReader]::new($csv2Path)
            try {
                while ($null -ne $reader2.ReadLine()) { $lineCount2++ }
            } finally {
                $reader2.Close()
            }
            $result.csv_0002_line_count = $lineCount2
            Write-Host "CSV 0002 total lines: $lineCount2"
        } catch {
            $errMsg = "Error reading CSV 0002: $($_.Exception.Message)"
            Write-Host "WARNING: $errMsg"
            $result.errors += $errMsg
        }
    } else {
        Write-Host "WARNING: CSV 0002 not found at $csv2Path"
        $result.errors += "CSV 0002 not found"
    }

    # ---------------------------------------------------------------
    # Check comparison summary file
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

    Write-Host "=== compare_surgical_cases export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
