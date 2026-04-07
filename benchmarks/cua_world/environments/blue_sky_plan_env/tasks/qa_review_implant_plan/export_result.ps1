# Post-task export script for qa_review_implant_plan.
# Collects verification artifacts and writes a structured JSON result.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_qa_review_implant_plan.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting qa_review_implant_plan results ==="

    $outputDir = "C:\Users\Docker\Documents\QAReview"
    $bspFile = "$outputDir\reviewed_plan.bsp"
    $beforeScreenshot = "$outputDir\before_correction.png"
    $afterScreenshot = "$outputDir\after_correction.png"
    $reportFile = "$outputDir\qa_report.txt"
    $resultFile = "$outputDir\qa_review_result.json"

    # ---------------------------------------------------------------
    # Initialize result object
    # ---------------------------------------------------------------
    $result = @{
        bsp_file_exists              = $false
        bsp_file_size_bytes          = 0
        bsp_file_modified            = 0
        before_screenshot_exists     = $false
        before_screenshot_size_bytes = 0
        after_screenshot_exists      = $false
        after_screenshot_size_bytes  = 0
        report_exists                = $false
        report_size_bytes            = 0
        report_content               = ""
        report_created_during_task   = $false
        task_start_time              = 0
        app_was_running              = $false
        has_implant_data             = $false
        implant_table_rows           = 0
        has_measurement_data         = $false
        measurement_table_rows       = 0
        sqlite_tables                = @()
        errors                       = @()
    }

    # ---------------------------------------------------------------
    # Read task start timestamp
    # ---------------------------------------------------------------
    $startFile = "$outputDir\task_start.txt"
    if (Test-Path $startFile) {
        $startContent = (Get-Content $startFile -Raw).Trim()
        try {
            $result.task_start_time = [long]$startContent
        } catch {
            $result.errors += "Could not parse task_start.txt: $startContent"
        }
    }

    # ---------------------------------------------------------------
    # Check if BSP is still running
    # ---------------------------------------------------------------
    $bspProc = Get-Process | Where-Object {
        $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*Launcher*"
    } | Select-Object -First 1
    $result.app_was_running = ($null -ne $bspProc)

    # ---------------------------------------------------------------
    # Check BSP project file
    # ---------------------------------------------------------------
    if (Test-Path $bspFile) {
        $bspInfo = Get-Item $bspFile
        $result.bsp_file_exists = $true
        $result.bsp_file_size_bytes = $bspInfo.Length
        $result.bsp_file_modified = [DateTimeOffset]::new($bspInfo.LastWriteTimeUtc).ToUnixTimeSeconds()
        Write-Host "BSP file found: $($bspInfo.Length) bytes, modified $($bspInfo.LastWriteTimeUtc)"
    } else {
        Write-Host "WARNING: BSP project file not found at $bspFile"
        $result.errors += "BSP file not found"
    }

    # ---------------------------------------------------------------
    # Check screenshot files
    # ---------------------------------------------------------------
    if (Test-Path $beforeScreenshot) {
        $ssInfo = Get-Item $beforeScreenshot
        $result.before_screenshot_exists = $true
        $result.before_screenshot_size_bytes = $ssInfo.Length
        Write-Host "Before screenshot found: $($ssInfo.Length) bytes"
    } else {
        Write-Host "WARNING: Before screenshot not found at $beforeScreenshot"
    }

    if (Test-Path $afterScreenshot) {
        $ssInfo = Get-Item $afterScreenshot
        $result.after_screenshot_exists = $true
        $result.after_screenshot_size_bytes = $ssInfo.Length
        Write-Host "After screenshot found: $($ssInfo.Length) bytes"
    } else {
        Write-Host "WARNING: After screenshot not found at $afterScreenshot"
    }

    # ---------------------------------------------------------------
    # Check QA report file
    # ---------------------------------------------------------------
    if (Test-Path $reportFile) {
        $reportInfo = Get-Item $reportFile
        $result.report_exists = $true
        $result.report_size_bytes = $reportInfo.Length
        $result.report_content = Get-Content $reportFile -Raw -ErrorAction SilentlyContinue

        # Check if report was created during the task
        $reportModified = [DateTimeOffset]::new($reportInfo.LastWriteTimeUtc).ToUnixTimeSeconds()
        if ($result.task_start_time -gt 0 -and $reportModified -ge $result.task_start_time) {
            $result.report_created_during_task = $true
        }
        Write-Host "QA report found: $($reportInfo.Length) bytes"
    } else {
        Write-Host "WARNING: QA report not found at $reportFile"
    }

    # ---------------------------------------------------------------
    # SQLite analysis of .bsp file
    # ---------------------------------------------------------------
    if ($result.bsp_file_exists) {
        try {
            $sqlitePath = $null
            $sqliteCandidates = @(
                "C:\Program Files\BlueSkyPlan\BlueSkyPlan4\sqlite3.exe",
                "C:\workspace\scripts\sqlite3.exe",
                "C:\Users\Docker\sqlite3.exe",
                "sqlite3.exe"
            )
            foreach ($candidate in $sqliteCandidates) {
                if (Test-Path $candidate -ErrorAction SilentlyContinue) {
                    $sqlitePath = $candidate
                    break
                }
                try {
                    $found = Get-Command $candidate -ErrorAction SilentlyContinue
                    if ($found) { $sqlitePath = $found.Source; break }
                } catch { }
            }

            if ($sqlitePath) {
                Write-Host "Using sqlite3 at: $sqlitePath"

                # List all tables
                $tables = & $sqlitePath $bspFile ".tables" 2>&1
                if ($tables -and $tables -is [string]) {
                    $tableList = $tables -split '\s+' | Where-Object { $_ -ne '' }
                    $result.sqlite_tables = @($tableList)
                    Write-Host "SQLite tables: $($tableList -join ', ')"
                }

                # Check for implant-related tables/data
                $implantKeywords = @("implant", "fixture", "abutment", "catalog", "component")
                foreach ($kw in $implantKeywords) {
                    foreach ($tbl in $result.sqlite_tables) {
                        if ($tbl -like "*$kw*") {
                            $result.has_implant_data = $true
                            try {
                                $count = & $sqlitePath $bspFile "SELECT COUNT(*) FROM [$tbl];" 2>&1
                                if ($count -match '^\d+$') {
                                    $result.implant_table_rows += [int]$count
                                }
                            } catch { }
                        }
                    }
                }

                # Check for measurement-related tables/data
                $measureKeywords = @("measure", "distance", "ruler", "annotation", "markup")
                foreach ($kw in $measureKeywords) {
                    foreach ($tbl in $result.sqlite_tables) {
                        if ($tbl -like "*$kw*") {
                            $result.has_measurement_data = $true
                            try {
                                $count = & $sqlitePath $bspFile "SELECT COUNT(*) FROM [$tbl];" 2>&1
                                if ($count -match '^\d+$') {
                                    $result.measurement_table_rows += [int]$count
                                }
                            } catch { }
                        }
                    }
                }

                # Fallback: check generic tables for implant/measurement data
                if (-not $result.has_implant_data) {
                    foreach ($tbl in $result.sqlite_tables) {
                        try {
                            $probe = & $sqlitePath $bspFile "SELECT * FROM [$tbl] LIMIT 1;" 2>&1
                            if ($probe -and ($probe -match "(?i)implant|fixture|bluesky|diameter|length")) {
                                $result.has_implant_data = $true
                                break
                            }
                        } catch { }
                    }
                }

                if (-not $result.has_measurement_data) {
                    foreach ($tbl in $result.sqlite_tables) {
                        try {
                            $probe = & $sqlitePath $bspFile "SELECT * FROM [$tbl] LIMIT 1;" 2>&1
                            if ($probe -and ($probe -match "(?i)measure|distance|ruler|length_mm")) {
                                $result.has_measurement_data = $true
                                break
                            }
                        } catch { }
                    }
                }
            } else {
                Write-Host "WARNING: sqlite3 not found - skipping database analysis"
                $result.errors += "sqlite3 not available for .bsp analysis"
            }
        } catch {
            $errMsg = "SQLite analysis failed: $($_.Exception.Message)"
            Write-Host "WARNING: $errMsg"
            $result.errors += $errMsg
        }
    }

    # ---------------------------------------------------------------
    # Write result JSON
    # ---------------------------------------------------------------
    $result | ConvertTo-Json -Depth 4 | Out-File -FilePath $resultFile -Encoding UTF8 -Force
    Write-Host "Result JSON written to: $resultFile"

    # Also write a copy to a well-known location for the verifier
    $result | ConvertTo-Json -Depth 4 | Out-File -FilePath "C:\workspace\task_result.json" -Encoding UTF8 -Force

    Write-Host "=== qa_review_implant_plan export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
