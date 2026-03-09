# Post-task export script for export_intraoperative_segment task.
# Checks if intraop_0001.csv exists, reads file properties (size, line count,
# header, tail lines, creation timestamp), and writes a structured result JSON
# for the verifier.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_export_intraop.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting export_intraoperative_segment results ==="

    $exportPath = "C:\Users\Docker\Desktop\intraop_0001.csv"
    $resultPath = "C:\Users\Docker\Desktop\task_result_intraop.json"
    $baselinePath = "C:\Users\Docker\task_baseline_intraop.json"

    # ---- Read baseline timestamp ----
    $taskStartUnix = 0
    if (Test-Path $baselinePath) {
        try {
            $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
            $taskStartUnix = [long]$baseline.task_start_unix
        } catch {
            Write-Host "WARNING: Could not parse baseline JSON: $($_.Exception.Message)"
        }
    }
    Write-Host "Task start unix: $taskStartUnix"

    # ---- Check CSV export file ----
    $csvExists = $false
    $csvSizeBytes = 0
    $csvLineCount = 0
    $csvHeaderLine = ""
    $csvTailLines = @()
    $csvCreationUnix = 0
    $csvLastWriteUnix = 0
    $csvCreatedAfterStart = $false
    $csvColumnNames = @()
    $csvColumnCount = 0
    $csvDataLineCount = 0

    if (Test-Path $exportPath) {
        $csvExists = $true
        $fi = Get-Item $exportPath
        $csvSizeBytes = $fi.Length
        $csvCreationUnix = [DateTimeOffset]::new($fi.CreationTimeUtc).ToUnixTimeSeconds()
        $csvLastWriteUnix = [DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()

        if ($taskStartUnix -gt 0 -and $csvLastWriteUnix -ge $taskStartUnix) {
            $csvCreatedAfterStart = $true
        }

        Write-Host "CSV file found: $exportPath ($csvSizeBytes bytes)"

        # Read file content for analysis
        try {
            # Read header line
            $reader = [System.IO.StreamReader]::new($exportPath)
            $csvHeaderLine = $reader.ReadLine()
            if ($csvHeaderLine) {
                # Parse column names from header
                $csvColumnNames = @($csvHeaderLine.Split(',') | ForEach-Object { $_.Trim().Trim('"') })
                $csvColumnCount = $csvColumnNames.Count
            }

            # Count all lines (including header)
            $lineCount = 1  # already read one line
            while ($null -ne $reader.ReadLine()) {
                $lineCount++
            }
            $csvLineCount = $lineCount
            $csvDataLineCount = [Math]::Max(0, $lineCount - 1)  # subtract header
            $reader.Close()
            $reader.Dispose()
            Write-Host "CSV header: $csvHeaderLine"
            Write-Host "CSV total lines: $csvLineCount (data lines: $csvDataLineCount)"
            Write-Host "CSV columns ($csvColumnCount): $($csvColumnNames -join ', ')"
        } catch {
            Write-Host "WARNING: Could not read CSV content: $($_.Exception.Message)"
        }

        # Read last few lines
        try {
            $allLines = [System.IO.File]::ReadAllLines($exportPath)
            $totalLines = $allLines.Count
            $tailCount = [Math]::Min(5, $totalLines)
            if ($tailCount -gt 0) {
                $csvTailLines = @($allLines[($totalLines - $tailCount)..($totalLines - 1)])
            }
        } catch {
            Write-Host "WARNING: Could not read tail lines: $($_.Exception.Message)"
        }

    } else {
        Write-Host "CSV file NOT found: $exportPath"
    }

    # ---- Build result JSON ----
    $result = @{
        task_start_unix       = $taskStartUnix
        export_timestamp      = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        csv_exists            = $csvExists
        csv_size_bytes        = $csvSizeBytes
        csv_line_count        = $csvLineCount
        csv_data_line_count   = $csvDataLineCount
        csv_header_line       = $csvHeaderLine
        csv_column_names      = $csvColumnNames
        csv_column_count      = $csvColumnCount
        csv_tail_lines        = $csvTailLines
        csv_creation_unix     = $csvCreationUnix
        csv_last_write_unix   = $csvLastWriteUnix
        csv_created_after_start = $csvCreatedAfterStart
        csv_path              = $exportPath
    }

    $resultJsonStr = $result | ConvertTo-Json -Depth 5
    $resultJsonStr | Out-File -FilePath $resultPath -Encoding utf8 -Force
    Write-Host "Result JSON written to: $resultPath"

    Write-Host "=== export_intraoperative_segment export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
