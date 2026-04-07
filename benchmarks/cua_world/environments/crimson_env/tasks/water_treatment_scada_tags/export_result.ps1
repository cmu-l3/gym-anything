# export_result.ps1 — water_treatment_scada_tags
# Runs after agent finishes. Uses Crimson's built-in "Export Tags" feature
# to dump the configured tag list to CSV, then normalises to JSON for the verifier.

$ErrorActionPreference = "Continue"

$logPath      = "C:\Users\Docker\task_post_water_treatment.log"
$resultPath   = "C:\Users\Docker\Desktop\CrimsonTasks\water_treatment_result.json"
$exportCsvPath = "C:\Users\Docker\Desktop\CrimsonTasks\water_treatment_tags_export.csv"
$projectPath  = "C:\Users\Docker\Documents\CrimsonProjects\water_treatment.c3"
$taskName     = "water_treatment_scada_tags"

try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting $taskName result ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # ── 1. Locate the saved project file ────────────────────────────────────
    $projectFound = Test-Path $projectPath
    Write-Host "Expected project path exists: $projectFound ($projectPath)"

    if (-not $projectFound) {
        # Fallback: search Documents for any .c3 file modified after task start
        $startTsFile = "C:\Users\Docker\task_start_ts_water_treatment.txt"
        $taskStart = 0
        if (Test-Path $startTsFile) {
            $taskStart = [int](Get-Content $startTsFile -Raw).Trim()
        }
        $recent = Get-ChildItem "C:\Users\Docker\Documents" -Recurse -Filter "*.c3" -ErrorAction SilentlyContinue |
                  Where-Object { [int][DateTimeOffset]::new($_.LastWriteTimeUtc).ToUnixTimeSeconds() -gt $taskStart } |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($recent) {
            $projectPath  = $recent.FullName
            $projectFound = $true
            Write-Host "Found recent project at: $projectPath"
        }
    }

    if (-not $projectFound) {
        Write-Host "No project file found. Agent did not save."
        @{ task = $taskName; project_found = $false; export_success = $false; tags = @() } |
            ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding UTF8 -Force
        exit 0
    }

    # ── 2. Ensure Crimson is running with the project open ───────────────────
    $crimsonRunning = $null -ne (Get-Process -Name "shexe" -ErrorAction SilentlyContinue | Select-Object -First 1)
    Write-Host "Crimson already running: $crimsonRunning"

    if (-not $crimsonRunning) {
        Write-Host "Re-launching Crimson with project: $projectPath"
        $crimsonExe = Find-CrimsonExe
        Launch-CrimsonInteractive -CrimsonExe $crimsonExe -ProjectPath $projectPath -WaitSeconds 18
        Wait-ForCrimsonProcess -TimeoutSeconds 30 | Out-Null
        Dismiss-CrimsonDialogsBestEffort -Retries 3 -InitialWaitSeconds 8 -BetweenRetriesSeconds 3
        Start-Sleep -Seconds 3
    }

    # ── 3. Navigate to Data Tags section (top-level, shows Export Tags link) ─
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 71; y = 467} | Out-Null
        Start-Sleep -Milliseconds 1800
        Write-Host "Navigated to Data Tags section."
    } catch {
        Write-Host "WARNING: Nav to Data Tags: $($_.Exception.Message)"
    }

    # ── 4. Click "Export Tags" link ──────────────────────────────────────────
    # Coordinates from evidence: Export Tags link at ~(244, 342) in 1280x720
    Remove-Item $exportCsvPath -Force -ErrorAction SilentlyContinue
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 244; y = 342} | Out-Null
        Start-Sleep -Milliseconds 2500
        Write-Host "Clicked Export Tags."
    } catch {
        Write-Host "WARNING: Export Tags click: $($_.Exception.Message)"
    }

    # ── 5. Handle Save dialog: paste the desired CSV path ────────────────────
    try {
        Set-Clipboard -Value $exportCsvPath
        Start-Sleep -Milliseconds 400
        # Select all text in the filename field and replace with our path
        Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "a")} | Out-Null
        Start-Sleep -Milliseconds 300
        Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "v")} | Out-Null
        Start-Sleep -Milliseconds 400
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "return"} | Out-Null
        Start-Sleep -Milliseconds 2500
        Write-Host "Save dialog handled."
    } catch {
        Write-Host "WARNING: Save dialog: $($_.Exception.Message)"
    }

    # Wait up to 8 s for the CSV file to appear
    $waited = 0
    while (-not (Test-Path $exportCsvPath) -and $waited -lt 8) {
        Start-Sleep -Seconds 1
        $waited++
    }
    Write-Host "Export CSV exists after wait: $(Test-Path $exportCsvPath)"

    # ── 6. Parse exported CSV into normalised tag array ──────────────────────
    $tags = @()
    $exportSuccess = $false

    if (Test-Path $exportCsvPath) {
        $exportSuccess = $true
        try {
            $csvContent = Get-Content $exportCsvPath -Raw -Encoding UTF8
            Write-Host "CSV content (first 500 chars):`n$($csvContent.Substring(0, [Math]::Min(500, $csvContent.Length)))"

            $csv = Import-Csv $exportCsvPath -ErrorAction Stop

            # Flexible column detection
            $headers = ($csv | Get-Member -MemberType NoteProperty).Name
            Write-Host "Detected CSV headers: $($headers -join ', ')"

            function Find-Col($hdrs, [string[]]$patterns) {
                foreach ($p in $patterns) {
                    $m = $hdrs | Where-Object { $_ -match $p } | Select-Object -First 1
                    if ($m) { return $m }
                }
                return $null
            }

            $colName  = Find-Col $headers @("(?i)^name$", "(?i)tagname", "(?i)^tag$")
            $colDesc  = Find-Col $headers @("(?i)desc")
            $colType  = Find-Col $headers @("(?i)datatype", "(?i)data.type", "(?i)type", "(?i)treat", "(?i)format")
            $colUnit  = Find-Col $headers @("(?i)^unit$", "(?i)engunit", "(?i)eng.*unit", "(?i)eu$")
            $colMin   = Find-Col $headers @("(?i)min")
            $colMax   = Find-Col $headers @("(?i)max")
            $colLabel = Find-Col $headers @("(?i)label", "(?i)engunit", "(?i)engineering")
            $colAlmLo = Find-Col $headers @("(?i)alarm.*lo", "(?i)lo.*alarm", "(?i)^lo$", "(?i)low")
            $colAlmHi = Find-Col $headers @("(?i)alarm.*hi", "(?i)hi.*alarm", "(?i)^hi$", "(?i)high")

            # Fallback: if no dedicated name column, first column is the name
            if (-not $colName -and $headers.Count -gt 0) { $colName = $headers[0] }

            Write-Host "Column mapping: name=$colName desc=$colDesc type=$colType unit=$colUnit min=$colMin max=$colMax label=$colLabel alarmLo=$colAlmLo alarmHi=$colAlmHi"

            foreach ($row in $csv) {
                $tagName = if ($colName)  { ($row.$colName).Trim()  } else { "" }
                if (-not $tagName) { continue }

                $safeNum = { param($v) if ($v) { try { [double]$v } catch { $null } } else { $null } }

                $tags += [ordered]@{
                    name        = $tagName
                    description = if ($colDesc)  { ($row.$colDesc).Trim()  } else { "" }
                    data_type   = if ($colType)  { ($row.$colType).Trim()  } else { "" }
                    unit        = if ($colUnit)  { ($row.$colUnit).Trim()  } else { "" }
                    min_value   = (& $safeNum (if ($colMin)   { $row.$colMin   } else { $null }))
                    max_value   = (& $safeNum (if ($colMax)   { $row.$colMax   } else { $null }))
                    label       = if ($colLabel) { ($row.$colLabel).Trim() } else { "" }
                    alarm_low   = (& $safeNum (if ($colAlmLo) { $row.$colAlmLo } else { $null }))
                    alarm_high  = (& $safeNum (if ($colAlmHi) { $row.$colAlmHi } else { $null }))
                }
            }
            Write-Host "Parsed $($tags.Count) tags from CSV."
        } catch {
            Write-Host "WARNING: CSV parse error: $($_.Exception.Message)"
        }
    }

    # ── 7. Write result JSON ─────────────────────────────────────────────────
    $result = [ordered]@{
        task            = $taskName
        project_found   = $projectFound
        export_success  = $exportSuccess
        tag_count       = $tags.Count
        tags            = $tags
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }
    $result | ConvertTo-Json -Depth 10 | Out-File $resultPath -Encoding UTF8 -Force
    Write-Host "Result JSON written to: $resultPath"

    Write-Host "=== Export complete: $taskName ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
