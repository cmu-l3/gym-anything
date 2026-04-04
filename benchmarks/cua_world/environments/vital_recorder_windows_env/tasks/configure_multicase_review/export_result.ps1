# Post-task export script for configure_multicase_review.
# Checks output files (CSV export and monitor screenshot),
# reads CSV metadata, and writes a result JSON for the verifier.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_configure_multicase_review.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting configure_multicase_review result ==="

    $csvFile = "C:\Users\Docker\Desktop\case_0003_review.csv"
    $screenshotFile = "C:\Users\Docker\Desktop\monitor_view_0003.png"
    $resultFile = "C:\Users\Docker\task_result_multicase.json"

    # Read baseline timestamp
    $taskStartTime = 0
    $baselineFile = "C:\Users\Docker\task_baseline_multicase.json"
    if (Test-Path $baselineFile) {
        try {
            $baselineData = Get-Content $baselineFile -Raw | ConvertFrom-Json
            $taskStartTime = $baselineData.timestamp
        } catch {
            Write-Host "WARNING: Could not parse baseline JSON"
        }
    }
    $taskEndTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # ------------------------------------------------------------------
    # Check 1: CSV export file
    # ------------------------------------------------------------------
    $csvExists = Test-Path $csvFile
    $csvSizeBytes = 0
    $csvLineCount = 0
    $csvHeaderLine = ""
    $csvColumnNames = @()

    if ($csvExists) {
        $csvInfo = Get-Item $csvFile
        $csvSizeBytes = $csvInfo.Length
        Write-Host "CSV file: $csvFile ($csvSizeBytes bytes)"

        try {
            # Read first line (header) and count total lines
            $allLines = Get-Content $csvFile -ErrorAction SilentlyContinue
            if ($allLines) {
                $csvLineCount = $allLines.Count
                $csvHeaderLine = $allLines[0]
                # Parse column names from header (comma-separated)
                $csvColumnNames = @($csvHeaderLine -split ',' | ForEach-Object { $_.Trim().Trim('"') })
                Write-Host "CSV header: $csvHeaderLine"
                Write-Host "CSV columns: $($csvColumnNames -join ', ')"
                Write-Host "CSV line count: $csvLineCount"
            }
        } catch {
            Write-Host "WARNING: Could not read CSV contents: $($_.Exception.Message)"
        }
    } else {
        Write-Host "WARNING: CSV file not found at $csvFile"

        # Check alternate locations on Desktop
        $altPaths = @(
            "C:\Users\Docker\Desktop\case_0003_review.CSV",
            "C:\Users\Docker\Desktop\0003.csv",
            "C:\Users\Docker\Desktop\case_0003.csv"
        )
        foreach ($alt in $altPaths) {
            if (Test-Path $alt) {
                Write-Host "Found alternate CSV at: $alt"
                Copy-Item $alt $csvFile -Force -ErrorAction SilentlyContinue
                $csvExists = Test-Path $csvFile
                if ($csvExists) {
                    $csvSizeBytes = (Get-Item $csvFile).Length
                    try {
                        $allLines = Get-Content $csvFile -ErrorAction SilentlyContinue
                        if ($allLines) {
                            $csvLineCount = $allLines.Count
                            $csvHeaderLine = $allLines[0]
                            $csvColumnNames = @($csvHeaderLine -split ',' | ForEach-Object { $_.Trim().Trim('"') })
                        }
                    } catch { }
                }
                break
            }
        }
    }

    # ------------------------------------------------------------------
    # Check 2: Monitor screenshot file
    # ------------------------------------------------------------------
    $screenshotExists = Test-Path $screenshotFile
    $screenshotSizeBytes = 0

    if ($screenshotExists) {
        $screenshotSizeBytes = (Get-Item $screenshotFile).Length
        Write-Host "Screenshot: $screenshotFile ($screenshotSizeBytes bytes)"
    } else {
        Write-Host "WARNING: Screenshot not found at $screenshotFile"

        # Check alternate locations
        $altPaths = @(
            "C:\Users\Docker\Desktop\monitor_view_0003.PNG",
            "C:\Users\Docker\Desktop\monitor_view.png",
            "C:\Users\Docker\Desktop\monitor_0003.png"
        )
        foreach ($alt in $altPaths) {
            if (Test-Path $alt) {
                Write-Host "Found alternate screenshot at: $alt"
                Copy-Item $alt $screenshotFile -Force -ErrorAction SilentlyContinue
                $screenshotExists = Test-Path $screenshotFile
                if ($screenshotExists) {
                    $screenshotSizeBytes = (Get-Item $screenshotFile).Length
                }
                break
            }
        }
    }

    # ------------------------------------------------------------------
    # Check 3: Analyze CSV for anesthetic monitoring columns
    # ------------------------------------------------------------------
    $hasAnestheticColumns = $false
    $anestheticColumnsFound = @()
    $expectedAnestheticCols = @("INSP_SEVO", "EXP_SEVO", "COMPLIANCE")

    foreach ($expected in $expectedAnestheticCols) {
        foreach ($col in $csvColumnNames) {
            if ($col -like "*$expected*") {
                $anestheticColumnsFound += $col
                $hasAnestheticColumns = $true
            }
        }
    }
    Write-Host "Anesthetic columns found: $($anestheticColumnsFound -join ', ')"

    # ------------------------------------------------------------------
    # Build result JSON
    # ------------------------------------------------------------------
    $result = @{
        task_start                = $taskStartTime
        task_end                  = $taskEndTime
        csv_file_exists           = $csvExists
        csv_file_size_bytes       = $csvSizeBytes
        csv_line_count            = $csvLineCount
        csv_header_line           = $csvHeaderLine
        csv_column_names          = $csvColumnNames
        csv_column_count          = $csvColumnNames.Count
        has_anesthetic_columns    = $hasAnestheticColumns
        anesthetic_columns_found  = $anestheticColumnsFound
        screenshot_exists         = $screenshotExists
        screenshot_size_bytes     = $screenshotSizeBytes
        timestamp                 = (Get-Date -Format "o")
    }

    $resultJson = $result | ConvertTo-Json -Depth 4
    $resultJson | Out-File -FilePath $resultFile -Encoding UTF8 -Force
    Write-Host "Result written to: $resultFile"
    Write-Host $resultJson

    Write-Host "=== configure_multicase_review export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
