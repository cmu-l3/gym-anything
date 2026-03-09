# Post-task export script for annotate_hemodynamic_events.
# Takes a screenshot, checks CSV export, inspects the .vital file for events,
# and writes a result JSON for the verifier.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_post_task_annotate_hemodynamic_events.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting annotate_hemodynamic_events result ==="

    $resultFile = "C:\Users\Docker\task_result_annotate.json"
    $csvPath = "C:\Users\Docker\Desktop\annotated_0001.csv"
    $dataFile = "C:\Users\Docker\Desktop\VitalRecorderData\0001.vital"
    $screenshotPath = "C:\Users\Docker\task_screenshot_annotate.png"

    # ------------------------------------------------------------------
    # Read baseline data
    # ------------------------------------------------------------------
    $taskStartTime = 0
    $initialEventCount = 4
    $baselineFile = "C:\Users\Docker\task_baseline_annotate.json"
    if (Test-Path $baselineFile) {
        try {
            $baseline = Get-Content $baselineFile -Raw | ConvertFrom-Json
            $taskStartTime = $baseline.task_start_time
            $initialEventCount = $baseline.initial_event_count
        } catch {
            Write-Host "WARNING: Could not parse baseline file: $($_.Exception.Message)"
        }
    }
    $taskEndTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # ------------------------------------------------------------------
    # Take a screenshot of the current state
    # ------------------------------------------------------------------
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        $bitmap.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
        Write-Host "Screenshot saved to: $screenshotPath"
    } catch {
        Write-Host "WARNING: Screenshot failed: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # Check 1: CSV export file
    # ------------------------------------------------------------------
    $csvExists = Test-Path $csvPath
    $csvSizeBytes = 0
    $csvLineCount = 0
    $csvHeaderLine = ""
    $csvHasVitalSignsCols = $false
    $csvVitalSignsCols = @()

    if ($csvExists) {
        $csvInfo = Get-Item $csvPath
        $csvSizeBytes = $csvInfo.Length
        Write-Host "CSV file found: $csvPath ($csvSizeBytes bytes)"

        try {
            # Read first few lines for header analysis
            $csvLines = Get-Content $csvPath -TotalCount 5 -ErrorAction SilentlyContinue
            $csvLineCount = (Get-Content $csvPath -ErrorAction SilentlyContinue | Measure-Object -Line).Lines

            if ($csvLines -and $csvLines.Count -gt 0) {
                $csvHeaderLine = $csvLines[0]
                Write-Host "CSV header: $csvHeaderLine"

                # Check for vital signs column names
                $vitalSignsKeywords = @("ART", "ECG", "PLETH", "CO2", "AWP", "SpO2", "HR", "BIS",
                                        "Solar8000", "Primus", "Orchestra", "FiO2", "EtCO2",
                                        "NIBP", "ABP", "CVP", "PPV", "SV", "CO", "SVR",
                                        "MAC", "TEMP", "RR", "TV", "MV", "PEEP", "PIP")
                $headerUpper = $csvHeaderLine.ToUpper()
                foreach ($kw in $vitalSignsKeywords) {
                    if ($headerUpper -like "*$kw*") {
                        $csvHasVitalSignsCols = $true
                        $csvVitalSignsCols += $kw
                    }
                }
                Write-Host "Vital signs columns found: $($csvVitalSignsCols -join ', ')"
            }
        } catch {
            Write-Host "WARNING: Could not read CSV contents: $($_.Exception.Message)"
        }
    } else {
        Write-Host "WARNING: CSV file not found at $csvPath"
        # Check alternate locations
        $altPaths = @(
            "C:\Users\Docker\Desktop\annotated_0001.CSV",
            "C:\Users\Docker\Desktop\0001.csv",
            "C:\Users\Docker\Desktop\VitalRecorderData\annotated_0001.csv",
            "C:\Users\Docker\Documents\annotated_0001.csv"
        )
        foreach ($alt in $altPaths) {
            if (Test-Path $alt) {
                Write-Host "Found CSV at alternate location: $alt"
                try {
                    Copy-Item $alt $csvPath -Force -ErrorAction SilentlyContinue
                    $csvExists = Test-Path $csvPath
                    if ($csvExists) {
                        $csvSizeBytes = (Get-Item $csvPath).Length
                    }
                } catch { }
                break
            }
        }
    }

    # ------------------------------------------------------------------
    # Check 2: .vital file modification (evidence of event additions)
    # ------------------------------------------------------------------
    $vitalFileExists = Test-Path $dataFile
    $vitalFileSizeBytes = 0
    $vitalFileModifiedAfterStart = $false
    $vitalFileLastWriteUnix = 0

    if ($vitalFileExists) {
        $vitalInfo = Get-Item $dataFile
        $vitalFileSizeBytes = $vitalInfo.Length
        $vitalFileLastWriteUnix = [long]([DateTimeOffset]$vitalInfo.LastWriteTimeUtc).ToUnixTimeSeconds()
        $vitalFileModifiedAfterStart = ($vitalFileLastWriteUnix -gt $taskStartTime)
        Write-Host "Vital file: $dataFile ($vitalFileSizeBytes bytes, modified_after_start=$vitalFileModifiedAfterStart)"
    }

    # ------------------------------------------------------------------
    # Check 3: Try to detect event count from the vital file
    # ------------------------------------------------------------------
    # Vital Recorder .vital files are SQLite databases containing event data.
    # We try to query the events table to count events added during the task.
    $totalEventCount = 0
    $newEventCount = 0
    $eventLabels = @()
    $eventsQuerySucceeded = $false

    if ($vitalFileExists -and $vitalFileSizeBytes -gt 0) {
        # Try sqlite3 if available
        $sqlite3 = $null
        $possibleSqlite3 = @(
            "C:\ProgramData\chocolatey\bin\sqlite3.exe",
            "C:\tools\sqlite3.exe",
            "C:\Windows\System32\sqlite3.exe",
            "sqlite3"
        )
        foreach ($p in $possibleSqlite3) {
            try {
                $testOut = & $p --version 2>&1
                if ($LASTEXITCODE -eq 0 -or $testOut -match "^\d+\.\d+") {
                    $sqlite3 = $p
                    break
                }
            } catch { }
        }

        if ($sqlite3) {
            Write-Host "Using sqlite3 at: $sqlite3"
            try {
                # List tables to find the events table
                $tableOutput = & $sqlite3 $dataFile ".tables" 2>&1
                $tableList = ($tableOutput -split '\s+') | Where-Object { $_ -ne '' }
                Write-Host "Tables in .vital file: $($tableList -join ', ')"

                # Try common event table names
                $eventTableNames = @("events", "event", "EVENT", "Events", "markers", "marker",
                                     "annotations", "annotation", "track_events", "event_list")
                $foundEventTable = $null

                foreach ($t in $eventTableNames) {
                    if ($tableList -contains $t) {
                        $foundEventTable = $t
                        break
                    }
                }

                # If no exact match, search for tables containing event-related keywords
                if (-not $foundEventTable) {
                    foreach ($t in $tableList) {
                        $tl = $t.ToLower()
                        if ($tl -like "*event*" -or $tl -like "*marker*" -or $tl -like "*annot*") {
                            $foundEventTable = $t
                            break
                        }
                    }
                }

                if ($foundEventTable) {
                    Write-Host "Found event table: $foundEventTable"

                    # Count total events
                    $countOutput = & $sqlite3 $dataFile "SELECT COUNT(*) FROM [$foundEventTable];" 2>&1
                    $totalEventCount = [int]($countOutput.Trim())
                    $newEventCount = $totalEventCount - $initialEventCount
                    if ($newEventCount -lt 0) { $newEventCount = 0 }
                    Write-Host "Total events: $totalEventCount (new: $newEventCount)"

                    # Get event labels (try common column names)
                    $labelCols = @("name", "label", "text", "description", "event_name", "event_text", "title", "comment")
                    foreach ($col in $labelCols) {
                        try {
                            $labelOutput = & $sqlite3 $dataFile "SELECT [$col] FROM [$foundEventTable];" 2>&1
                            if ($LASTEXITCODE -eq 0 -and $labelOutput) {
                                $eventLabels = @($labelOutput | Where-Object { $_ -ne '' })
                                Write-Host "Event labels ($col): $($eventLabels -join '; ')"
                                $eventsQuerySucceeded = $true
                                break
                            }
                        } catch { }
                    }

                    # If no label column found, try selecting all columns from the first row
                    if (-not $eventsQuerySucceeded) {
                        try {
                            $allOutput = & $sqlite3 $dataFile "SELECT * FROM [$foundEventTable] LIMIT 10;" 2>&1
                            Write-Host "Raw event data (first 10 rows):"
                            $allOutput | ForEach-Object { Write-Host "  $_" }
                            $eventsQuerySucceeded = $true
                        } catch { }
                    }
                } else {
                    Write-Host "WARNING: No event table found in .vital file"
                    Write-Host "Available tables: $($tableList -join ', ')"

                    # Fallback: count all tables with data as evidence
                    foreach ($t in $tableList) {
                        if ($t -notlike "sqlite_*") {
                            try {
                                $schema = & $sqlite3 $dataFile "PRAGMA table_info([$t]);" 2>&1
                                Write-Host "  Table $t schema: $($schema -join ' | ')"
                            } catch { }
                        }
                    }
                }
            } catch {
                Write-Host "WARNING: SQLite query failed: $($_.Exception.Message)"
            }
        } else {
            Write-Host "sqlite3 not available, trying Python fallback..."
            try {
                $pythonScript = @"
import sqlite3, json, sys
try:
    conn = sqlite3.connect(r'$dataFile')
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall()]
    result = {"tables": tables, "total_events": 0, "event_labels": [], "event_table": None}
    event_kw = ["event", "marker", "annot"]
    for t in tables:
        tl = t.lower()
        for kw in event_kw:
            if kw in tl:
                result["event_table"] = t
                cursor.execute(f"SELECT COUNT(*) FROM [{t}]")
                result["total_events"] = cursor.fetchone()[0]
                # Try to get labels
                cursor.execute(f"PRAGMA table_info([{t}])")
                cols = [c[1] for c in cursor.fetchall()]
                label_cols = ["name", "label", "text", "description", "event_name", "title", "comment"]
                for lc in label_cols:
                    if lc in [c.lower() for c in cols]:
                        actual_col = cols[[c.lower() for c in cols].index(lc)]
                        cursor.execute(f"SELECT [{actual_col}] FROM [{t}]")
                        result["event_labels"] = [r[0] for r in cursor.fetchall() if r[0]]
                        break
                break
        if result["event_table"]:
            break
    conn.close()
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
"@
                $pyOut = python -c $pythonScript 2>&1
                $pyResult = $pyOut | ConvertFrom-Json
                if ($pyResult.total_events) {
                    $totalEventCount = $pyResult.total_events
                    $newEventCount = $totalEventCount - $initialEventCount
                    if ($newEventCount -lt 0) { $newEventCount = 0 }
                }
                if ($pyResult.event_labels) {
                    $eventLabels = $pyResult.event_labels
                }
                $eventsQuerySucceeded = ($null -ne $pyResult.event_table)
                Write-Host "Python SQLite analysis: total_events=$totalEventCount, new=$newEventCount"
            } catch {
                Write-Host "WARNING: Python SQLite analysis failed: $($_.Exception.Message)"
            }
        }
    }

    # ------------------------------------------------------------------
    # Build result JSON
    # ------------------------------------------------------------------
    $result = @{
        task_start_time             = $taskStartTime
        task_end_time               = $taskEndTime
        initial_event_count         = $initialEventCount
        csv_exists                  = $csvExists
        csv_size_bytes              = $csvSizeBytes
        csv_line_count              = $csvLineCount
        csv_header_line             = $csvHeaderLine
        csv_has_vital_signs_cols    = $csvHasVitalSignsCols
        csv_vital_signs_cols        = $csvVitalSignsCols
        vital_file_exists           = $vitalFileExists
        vital_file_size_bytes       = $vitalFileSizeBytes
        vital_file_modified         = $vitalFileModifiedAfterStart
        vital_file_last_write_unix  = $vitalFileLastWriteUnix
        total_event_count           = $totalEventCount
        new_event_count             = $newEventCount
        event_labels                = $eventLabels
        events_query_succeeded      = $eventsQuerySucceeded
        screenshot_path             = $screenshotPath
        screenshot_exists           = (Test-Path $screenshotPath)
        timestamp                   = (Get-Date -Format "o")
    }

    $resultJson = $result | ConvertTo-Json -Depth 4
    $resultJson | Out-File -FilePath $resultFile -Encoding UTF8 -Force
    Write-Host "Result written to: $resultFile"
    Write-Host $resultJson

    Write-Host "=== annotate_hemodynamic_events export complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
