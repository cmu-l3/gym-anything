# export_result.ps1 — boiler_drum_3element_control
# Collects file existence, size, timestamp, and tag export into a result JSON.

$ErrorActionPreference = "Continue"

$logPath       = "C:\Users\Docker\task_post_boiler_drum.log"
$resultPath    = "C:\Users\Docker\Desktop\CrimsonTasks\boiler_drum_result.json"
$exportCsvPath = "C:\Users\Docker\Desktop\CrimsonTasks\boiler_drum_tags_export.csv"
$projectPath   = "C:\Users\Docker\Documents\CrimsonProjects\boiler_drum_3element.c3"
$taskName      = "boiler_drum_3element_control"

try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting $taskName result ==="
    . "C:\workspace\scripts\task_utils.ps1"

    # ── 1. Locate project file ─────────────────────────────────────
    $projectFound = Test-Path $projectPath
    $fileSize = 0
    $fileCreatedDuringTask = $false

    if (-not $projectFound) {
        # Fallback: search for any .c3 created after task start
        $startTsFile = "C:\Users\Docker\task_start_ts_boiler_drum.txt"
        $taskStart = 0
        if (Test-Path $startTsFile) { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() }
        $recent = Get-ChildItem "C:\Users\Docker\Documents" -Recurse -Filter "*.c3" -ErrorAction SilentlyContinue |
                  Where-Object { [int][DateTimeOffset]::new($_.LastWriteTimeUtc).ToUnixTimeSeconds() -gt $taskStart } |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($recent) { $projectPath = $recent.FullName; $projectFound = $true }
    }

    if ($projectFound) {
        $fi = Get-Item $projectPath
        $fileSize = $fi.Length
        $startTsFile = "C:\Users\Docker\task_start_ts_boiler_drum.txt"
        $taskStart = 0
        if (Test-Path $startTsFile) { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() }
        $fileMod = [int][DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds()
        $fileCreatedDuringTask = ($fileMod -gt $taskStart)
    }

    Write-Host "Project found: $projectFound ($projectPath), size=$fileSize, during_task=$fileCreatedDuringTask"

    if (-not $projectFound) {
        @{
            task                    = $taskName
            project_found           = $false
            file_size               = 0
            file_created_during_task = $false
            export_success          = $false
            tags                    = @()
        } | ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding UTF8 -Force
        Write-Host "No project found. Result written."
        exit 0
    }

    # ── 2. Ensure Crimson is running with the project ──────────────
    $crimsonRunning = $null -ne (Get-Process -Name "shexe" -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $crimsonRunning) {
        $crimsonExe = Find-CrimsonExe
        Launch-CrimsonInteractive -CrimsonExe $crimsonExe -ProjectPath $projectPath -WaitSeconds 18
        Wait-ForCrimsonProcess -TimeoutSeconds 30 | Out-Null
        try {
            Dismiss-CrimsonDialogsBestEffort -Retries 3 -InitialWaitSeconds 8 -BetweenRetriesSeconds 3
        } catch { Write-Host "WARNING: Dialog dismissal: $($_.Exception.Message)" }
        Start-Sleep -Seconds 3
    }

    # ── 3. Navigate to Data Tags section ───────────────────────────
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 71; y = 467} | Out-Null
        Start-Sleep -Milliseconds 1800
    } catch { Write-Host "WARNING: Nav DataTags: $($_.Exception.Message)" }

    # ── 4. Click Export Tags ───────────────────────────────────────
    Remove-Item $exportCsvPath -Force -ErrorAction SilentlyContinue
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 244; y = 342} | Out-Null
        Start-Sleep -Milliseconds 2500
    } catch { Write-Host "WARNING: Export Tags click: $($_.Exception.Message)" }

    # ── 5. Save dialog — paste path and confirm ────────────────────
    try {
        Set-Clipboard -Value $exportCsvPath
        Start-Sleep -Milliseconds 400
        Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "a")} | Out-Null
        Start-Sleep -Milliseconds 300
        Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "v")} | Out-Null
        Start-Sleep -Milliseconds 400
        Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "return"} | Out-Null
        Start-Sleep -Milliseconds 2500
    } catch { Write-Host "WARNING: Save dialog: $($_.Exception.Message)" }

    # Wait for export file
    $waited = 0
    while (-not (Test-Path $exportCsvPath) -and $waited -lt 8) { Start-Sleep -Seconds 1; $waited++ }

    # ── 6. Parse CSV export ────────────────────────────────────────
    $tags = @()
    $exportSuccess = (Test-Path $exportCsvPath)
    if ($exportSuccess) {
        try {
            $csv = Import-Csv $exportCsvPath -ErrorAction Stop
            $headers = ($csv | Get-Member -MemberType NoteProperty).Name
            function Find-Col($hdrs, [string[]]$patterns) {
                foreach ($p in $patterns) {
                    $m = $hdrs | Where-Object { $_ -match $p } | Select-Object -First 1
                    if ($m) { return $m }
                }
                return $null
            }
            $colName  = Find-Col $headers @("(?i)^name$","(?i)tagname","(?i)^tag$")
            $colDesc  = Find-Col $headers @("(?i)desc")
            $colType  = Find-Col $headers @("(?i)datatype","(?i)data.type","(?i)treat","(?i)type","(?i)format")
            $colUnit  = Find-Col $headers @("(?i)^unit$","(?i)engunit","(?i)eu$")
            $colMin   = Find-Col $headers @("(?i)min")
            $colMax   = Find-Col $headers @("(?i)max")
            $colLabel = Find-Col $headers @("(?i)label","(?i)engunit","(?i)engineering")
            $colAlmLo = Find-Col $headers @("(?i)alarm.*lo","(?i)lo.*alarm","(?i)^lo$","(?i)low")
            $colAlmHi = Find-Col $headers @("(?i)alarm.*hi","(?i)hi.*alarm","(?i)^hi$","(?i)high")
            if (-not $colName -and $headers.Count -gt 0) { $colName = $headers[0] }
            $safeNum = { param($v) if ($v) { try { [double]$v } catch { $null } } else { $null } }
            foreach ($row in $csv) {
                $tn = if ($colName) { ($row.$colName).Trim() } else { "" }
                if (-not $tn) { continue }
                $tags += [ordered]@{
                    name        = $tn
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
            Write-Host "Parsed $($tags.Count) tags from export CSV."
        } catch {
            Write-Host "WARNING: CSV parse: $($_.Exception.Message)"
        }
    }

    # ── 7. Read binary .c3 for additional context strings ──────────
    $binaryContexts = @{}
    if ($projectFound) {
        try {
            $raw = [System.IO.File]::ReadAllText($projectPath, [System.Text.Encoding]::GetEncoding("ISO-8859-1"))
            foreach ($tagName in @("LT_100","FT_100","FT_101","PT_100","CV_100",
                                   "FT_100_COMP","FT_101_COMP","MASS_BAL","TT_100",
                                   "DrumLevelControl","DrumLevelLog")) {
                $idx = $raw.IndexOf($tagName)
                if ($idx -ge 0) {
                    $start = [Math]::Max(0, $idx - 50)
                    $end = [Math]::Min($raw.Length, $idx + $tagName.Length + 200)
                    $ctx = $raw.Substring($start, $end - $start) -replace '[^\x20-\x7E]', '.'
                    $binaryContexts[$tagName] = $ctx
                }
            }
            Write-Host "Binary context extracted for $($binaryContexts.Count) identifiers."
        } catch {
            Write-Host "WARNING: Binary read: $($_.Exception.Message)"
        }
    }

    # ── 8. Write result JSON ───────────────────────────────────────
    [ordered]@{
        task                     = $taskName
        project_found            = $projectFound
        project_path             = $projectPath
        file_size                = $fileSize
        file_created_during_task = $fileCreatedDuringTask
        export_success           = $exportSuccess
        tag_count                = $tags.Count
        tags                     = $tags
        binary_contexts          = $binaryContexts
        export_timestamp         = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    } | ConvertTo-Json -Depth 10 | Out-File $resultPath -Encoding UTF8 -Force

    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export complete: $taskName ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
