Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting emissions_readiness_assessment results ==="

$resultJson   = "C:\Users\Docker\emissions_readiness_assessment_result.json"
$reportFile   = "C:\Users\Docker\Desktop\MultiecuscanTasks\emissions_readiness_report.txt"
$tsFile       = "C:\Users\Docker\Desktop\MultiecuscanTasks\emissions_readiness_assessment_start_timestamp.txt"

# Read start timestamp
$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

# Wait briefly for any final writes
Start-Sleep -Seconds 3

# Stop Multiecuscan
Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Build result object
$result = @{
    task_name              = "emissions_readiness_assessment"
    start_timestamp        = $startTimestamp
    report_exists          = $false
    report_file_size       = 0
    report_file_mtime      = 0
    report_content         = ""
    has_ecu_section        = $false
    has_readiness_table    = $false
    has_dtc_section        = $false
    has_verdict            = $false
    has_drive_cycle        = $false
    dtc_codes_found        = @()
    readiness_monitors     = @()
    verdict_value          = ""
    catalyst_monitor_mentioned = $false
    evap_monitor_mentioned = $false
    o2_sensor_mentioned    = $false
    mot_reference          = $false
    vehicle_id_present     = $false
}

if (Test-Path $reportFile) {
    $fileInfo = Get-Item $reportFile
    $result.report_exists    = $true
    $result.report_file_size = $fileInfo.Length
    $result.report_file_mtime = [int][double]::Parse(
        (Get-Date $fileInfo.LastWriteTimeUtc -UFormat %s))

    $raw = Get-Content $reportFile -Raw -ErrorAction SilentlyContinue
    if ($raw) {
        if ($raw.Length -gt 60000) { $raw = $raw.Substring(0, 60000) }
        $result.report_content = $raw

        # Vehicle / ECU identification
        if ($raw -match "(?i)(Alfa\s*Romeo|MiTo|ECU|Part\s*Number|VIN|1\.4|TB|955A8)") {
            $result.has_ecu_section = $true
        }
        if ($raw -match "(?i)(ZAR955|MiTo|Alfa Romeo|1368)") {
            $result.vehicle_id_present = $true
        }

        # Readiness monitor table
        if ($raw -match "(?i)(readiness|monitor|complete|incomplete|ready|not\s+support)") {
            $result.has_readiness_table = $true
        }
        # Individual monitors
        $monitors = @()
        if ($raw -match "(?i)catalyst") { $monitors += "catalyst"; $result.catalyst_monitor_mentioned = $true }
        if ($raw -match "(?i)(evap|evaporat)") { $monitors += "evap"; $result.evap_monitor_mentioned = $true }
        if ($raw -match "(?i)(oxygen|O2\s*sensor|lambda)") { $monitors += "o2_sensor"; $result.o2_sensor_mentioned = $true }
        if ($raw -match "(?i)(EGR)") { $monitors += "egr" }
        if ($raw -match "(?i)(secondary\s*air|air\s*system)") { $monitors += "secondary_air" }
        if ($raw -match "(?i)(heated\s*catalyst|warm\s*up)") { $monitors += "heated_catalyst" }
        $result.readiness_monitors = $monitors

        # DTC section
        if ($raw -match "(?i)(DTC|fault\s*code|diagnostic\s*trouble|error\s*code|no\s*(stored\s*)?faults?)") {
            $result.has_dtc_section = $true
        }
        $dtcMatches = [regex]::Matches($raw, "[PBCU][01]\d{3}")
        $dtcCodes = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $dtcCodes) { $dtcCodes += $m.Value }
        }
        $result.dtc_codes_found = $dtcCodes

        # MOT verdict
        if ($raw -match "(?i)(READY|NOT\s*READY|CONDITIONAL|FAIL|PASS|verdict)") {
            $result.has_verdict = $true
            if ($raw -match "(?i)\b(NOT\s*READY)\b") { $result.verdict_value = "NOT_READY" }
            elseif ($raw -match "(?i)\bCONDITIONAL\b") { $result.verdict_value = "CONDITIONAL" }
            elseif ($raw -match "(?i)\bREADY\b") { $result.verdict_value = "READY" }
        }

        # Drive cycle guidance
        if ($raw -match "(?i)(drive\s*cycle|warm.up|idle|motorway|highway|city\s*driving|miles?\s*(to|needed))") {
            $result.has_drive_cycle = $true
        }

        # MOT-specific reference
        if ($raw -match "(?i)(MOT|ministry\s*of\s*transport|road\s*worthiness|UK\s*(test|regulation))") {
            $result.mot_reference = $true
        }
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Report exists: $($result.report_exists)"
Write-Host "Has readiness table: $($result.has_readiness_table)"
Write-Host "Has verdict: $($result.has_verdict) ($($result.verdict_value))"
Write-Host "DTCs found: $($result.dtc_codes_found -join ', ')"
Write-Host "Monitors mentioned: $($result.readiness_monitors -join ', ')"
