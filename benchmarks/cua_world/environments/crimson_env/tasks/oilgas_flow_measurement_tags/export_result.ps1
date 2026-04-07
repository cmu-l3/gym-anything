# export_result.ps1 — oilgas_flow_measurement_tags
# Uses Crimson's Export Tags feature to dump configured tags, then writes result JSON.

$ErrorActionPreference = "Continue"

$logPath       = "C:\Users\Docker\task_post_oilgas_flow.log"
$resultPath    = "C:\Users\Docker\Desktop\CrimsonTasks\oilgas_flow_result.json"
$exportCsvPath = "C:\Users\Docker\Desktop\CrimsonTasks\oilgas_flow_tags_export.csv"
$projectPath   = "C:\Users\Docker\Documents\CrimsonProjects\oilgas_flow.c3"
$taskName      = "oilgas_flow_measurement_tags"

try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Exporting $taskName result ==="
    . "C:\workspace\scripts\task_utils.ps1"

    # 1. Locate project
    $projectFound = Test-Path $projectPath
    if (-not $projectFound) {
        $startTsFile = "C:\Users\Docker\task_start_ts_oilgas_flow.txt"
        $taskStart = 0
        if (Test-Path $startTsFile) { $taskStart = [int](Get-Content $startTsFile -Raw).Trim() }
        $recent = Get-ChildItem "C:\Users\Docker\Documents" -Recurse -Filter "*.c3" -ErrorAction SilentlyContinue |
                  Where-Object { [int][DateTimeOffset]::new($_.LastWriteTimeUtc).ToUnixTimeSeconds() -gt $taskStart } |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($recent) { $projectPath = $recent.FullName; $projectFound = $true }
    }
    Write-Host "Project found: $projectFound ($projectPath)"

    if (-not $projectFound) {
        @{ task = $taskName; project_found = $false; export_success = $false; tags = @() } |
            ConvertTo-Json -Depth 5 | Out-File $resultPath -Encoding UTF8 -Force
        exit 0
    }

    # 2. Ensure Crimson is running
    $crimsonRunning = $null -ne (Get-Process -Name "shexe" -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $crimsonRunning) {
        $crimsonExe = Find-CrimsonExe
        Launch-CrimsonInteractive -CrimsonExe $crimsonExe -ProjectPath $projectPath -WaitSeconds 18
        Wait-ForCrimsonProcess -TimeoutSeconds 30 | Out-Null
        Dismiss-CrimsonDialogsBestEffort -Retries 3 -InitialWaitSeconds 8 -BetweenRetriesSeconds 3
        Start-Sleep -Seconds 3
    }

    # 3. Navigate to Data Tags section
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 71; y = 467} | Out-Null
        Start-Sleep -Milliseconds 1800
    } catch { Write-Host "WARNING: Nav DataTags: $($_.Exception.Message)" }

    # 4. Click Export Tags
    Remove-Item $exportCsvPath -Force -ErrorAction SilentlyContinue
    try {
        Invoke-PyAutoGUICommand -Command @{action = "click"; x = 244; y = 342} | Out-Null
        Start-Sleep -Milliseconds 2500
    } catch { Write-Host "WARNING: Export Tags click: $($_.Exception.Message)" }

    # 5. Save dialog
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

    $waited = 0
    while (-not (Test-Path $exportCsvPath) -and $waited -lt 8) { Start-Sleep -Seconds 1; $waited++ }

    # 6. Parse CSV
    $tags = @()
    $exportSuccess = (Test-Path $exportCsvPath)
    if ($exportSuccess) {
        try {
            $csv = Import-Csv $exportCsvPath -ErrorAction Stop
            $headers = ($csv | Get-Member -MemberType NoteProperty).Name
            function Find-Col2($hdrs, [string[]]$patterns) {
                foreach ($p in $patterns) {
                    $m = $hdrs | Where-Object { $_ -match $p } | Select-Object -First 1
                    if ($m) { return $m }
                }
                return $null
            }
            $colName  = Find-Col2 $headers @("(?i)^name$","(?i)tagname","(?i)^tag$")
            $colDesc  = Find-Col2 $headers @("(?i)desc")
            $colType  = Find-Col2 $headers @("(?i)datatype","(?i)data.type","(?i)treat","(?i)type","(?i)format")
            $colUnit  = Find-Col2 $headers @("(?i)^unit$","(?i)engunit","(?i)eu$")
            $colMin   = Find-Col2 $headers @("(?i)min")
            $colMax   = Find-Col2 $headers @("(?i)max")
            $colLabel = Find-Col2 $headers @("(?i)label","(?i)engunit","(?i)engineering")
            $colAlmLo = Find-Col2 $headers @("(?i)alarm.*lo","(?i)lo.*alarm","(?i)^lo$","(?i)low")
            $colAlmHi = Find-Col2 $headers @("(?i)alarm.*hi","(?i)hi.*alarm","(?i)^hi$","(?i)high")
            if (-not $colName -and $headers.Count -gt 0) { $colName = $headers[0] }
            $safeNum = { param($v) if ($v) { try { [double]$v } catch { $null } } else { $null } }
            foreach ($row in $csv) {
                $tn2 = if ($colName) { ($row.$colName).Trim() } else { "" }
                if (-not $tn2) { continue }
                $tags += [ordered]@{
                    name        = $tn2
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
            Write-Host "Parsed $($tags.Count) tags."
        } catch { Write-Host "WARNING: CSV parse: $($_.Exception.Message)" }
    }

    # 7. Write result
    [ordered]@{
        task            = $taskName
        project_found   = $projectFound
        export_success  = $exportSuccess
        tag_count       = $tags.Count
        tags            = $tags
        export_timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    } | ConvertTo-Json -Depth 10 | Out-File $resultPath -Encoding UTF8 -Force

    Write-Host "Result written to: $resultPath"
    Write-Host "=== Export complete: $taskName ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
