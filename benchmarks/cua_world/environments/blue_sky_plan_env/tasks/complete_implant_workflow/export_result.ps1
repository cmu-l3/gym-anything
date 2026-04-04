# Post-task export script for complete_implant_workflow.
# Collects verification artifacts and writes a structured JSON result.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_complete_implant_workflow.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting complete_implant_workflow results ==="

    $taskDir = "C:\Users\Docker\Desktop\BlueSkyPlanTasks"
    $bspFile = "$taskDir\complete_plan.bsp"
    $screenshotFile = "$taskDir\complete_plan_screenshot.png"
    $resultFile = "$taskDir\complete_workflow_result.json"

    # ---------------------------------------------------------------
    # Initialize result object
    # ---------------------------------------------------------------
    $result = @{
        bsp_file_exists       = $false
        bsp_file_size_bytes   = 0
        bsp_file_modified     = 0
        screenshot_exists     = $false
        screenshot_size_bytes = 0
        task_start_time       = 0
        has_implant_data      = $false
        has_measurement_data  = $false
        implant_table_rows    = 0
        measurement_table_rows = 0
        sqlite_tables         = @()
        errors                = @()
    }

    # ---------------------------------------------------------------
    # Read task start timestamp
    # ---------------------------------------------------------------
    $startFile = "$taskDir\task_start.txt"
    if (Test-Path $startFile) {
        $startContent = (Get-Content $startFile -Raw).Trim()
        try {
            $result.task_start_time = [long]$startContent
        } catch {
            $result.errors += "Could not parse task_start.txt: $startContent"
        }
    }

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
    # Check screenshot file
    # ---------------------------------------------------------------
    if (Test-Path $screenshotFile) {
        $ssInfo = Get-Item $screenshotFile
        $result.screenshot_exists = $true
        $result.screenshot_size_bytes = $ssInfo.Length
        Write-Host "Screenshot found: $($ssInfo.Length) bytes"
    } else {
        Write-Host "WARNING: Screenshot file not found at $screenshotFile"
        $result.errors += "Screenshot file not found"
    }

    # ---------------------------------------------------------------
    # SQLite analysis of .bsp file (BSP projects are SQLite databases)
    # ---------------------------------------------------------------
    if ($result.bsp_file_exists) {
        try {
            # BSP .bsp files are SQLite databases. Try to query them.
            $sqlitePath = $null
            # Check common locations for sqlite3
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
                # Also check if it's on PATH
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
                            # Try to count rows
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
                            # Try to count rows
                            try {
                                $count = & $sqlitePath $bspFile "SELECT COUNT(*) FROM [$tbl];" 2>&1
                                if ($count -match '^\d+$') {
                                    $result.measurement_table_rows += [int]$count
                                }
                            } catch { }
                        }
                    }
                }

                # If no keyword match, try generic queries for implant data
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

                # Generic check for measurement data
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

                # Fallback: use file size as a heuristic
                # A bare DICOM-only project is typically <400KB.
                # Adding implants pushes it well above 500KB.
                if ($result.bsp_file_size_bytes -gt 500000) {
                    Write-Host "BSP file is large (>500KB), likely contains implant/measurement data"
                    # Don't set has_implant_data here -- verifier will use size heuristic
                }
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

    Write-Host "=== complete_implant_workflow export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
