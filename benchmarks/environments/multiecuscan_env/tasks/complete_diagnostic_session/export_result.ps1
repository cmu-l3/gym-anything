Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting complete_diagnostic_session results ==="

$resultJson = "C:\Users\Docker\Desktop\MultiecuscanTasks\complete_diagnostic_session_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\full_session_report.txt"
$tsFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\complete_diagnostic_session_start_timestamp.txt"

$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

Start-Sleep -Seconds 3
Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$result = @{
    task_name = "complete_diagnostic_session"
    start_timestamp = $startTimestamp
    report_exists = $false
    report_file_size = 0
    report_file_mtime = 0
    report_content = ""
    # Section checks
    has_vehicle_info = $false
    has_engine_ecu_info = $false
    has_engine_dtcs = $false
    has_parameter_analysis = $false
    has_body_dtcs = $false
    has_overall_assessment = $false
    # Detailed data
    section_count = 0
    dtc_codes_found = @()
    engine_dtc_count = 0
    body_dtc_count = 0
    parameters_documented = @()
    has_real_data_comparison = $false
    has_repair_recommendations = $false
    has_urgency_levels = $false
    has_date_time = $false
    report_word_count = 0
}

if (Test-Path $reportFile) {
    $fileInfo = Get-Item $reportFile
    $result.report_exists = $true
    $result.report_file_size = $fileInfo.Length
    $result.report_file_mtime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTimeUtc -UFormat %s))

    $content = Get-Content $reportFile -Raw -ErrorAction SilentlyContinue
    if ($content) {
        if ($content.Length -gt 50000) { $content = $content.Substring(0, 50000) }
        $result.report_content = $content
        $result.report_word_count = ($content -split '\s+').Count

        # Section A: Vehicle & Session Info
        if ($content -match "(?i)(Vehicle|Session|Ducato|Fiat)" -and $content -match "(?i)(Date|Time|Session)") {
            $result.has_vehicle_info = $true
        }
        if ($content -match "(?i)\d{4}[-/]\d{2}[-/]\d{2}") {
            $result.has_date_time = $true
        }

        # Section B: Engine ECU Identification
        if ($content -match "(?i)(Engine\s*ECU|EDC16|Bosch)" -and $content -match "(?i)(Part\s*Number|Hardware|Software)") {
            $result.has_engine_ecu_info = $true
        }

        # Section C: Engine DTCs
        if ($content -match "(?i)(Engine\s*DTC|Engine\s*(Error|Fault|Trouble))") {
            $result.has_engine_dtcs = $true
        } elseif ($content -match "(?i)DTC" -and $content -match "(?i)Engine") {
            $result.has_engine_dtcs = $true
        }

        # Extract all DTCs
        $dtcMatches = [regex]::Matches($content, "[PBCU][01]\d{3}")
        $dtcCodes = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $dtcCodes) { $dtcCodes += $m.Value }
        }
        $result.dtc_codes_found = $dtcCodes

        # Count engine vs body DTCs (P-codes = engine, B-codes = body, U-codes = network)
        $result.engine_dtc_count = ($dtcCodes | Where-Object { $_ -match "^P" }).Count
        $result.body_dtc_count = ($dtcCodes | Where-Object { $_ -match "^[BU]" }).Count

        # Section D: Parameter Analysis
        $params = @()
        if ($content -match "(?i)RPM") { $params += "RPM" }
        if ($content -match "(?i)(Coolant|ECT|Temperatur)") { $params += "Coolant" }
        if ($content -match "(?i)(Voltage|Battery)") { $params += "Voltage" }
        if ($content -match "(?i)(Fuel\s*Rail|Manifold|Throttle|Pressure)") { $params += "FuelRail_or_Throttle" }
        $result.parameters_documented = $params
        if ($params.Count -ge 3) {
            $result.has_parameter_analysis = $true
        }

        # Real data comparison
        if ($content -match "(?i)(Real|Recorded|Drive|Session|Comparison|Compare|Toyota|actual)") {
            $result.has_real_data_comparison = $true
        }

        # Section E: Body Computer DTCs
        if ($content -match "(?i)(Body\s*(Computer|DTC|Module|Control)|BCM)") {
            $result.has_body_dtcs = $true
        }

        # Section F: Overall Assessment
        if ($content -match "(?i)(Overall|Assessment|Summary|Conclusion|Health)") {
            $result.has_overall_assessment = $true
        }
        if ($content -match "(?i)(Repair|Fix|Replace|Service|Maintenance)") {
            $result.has_repair_recommendations = $true
        }
        if ($content -match "(?i)(Urgent|Priority|Critical|High|Medium|Low|Immediate)") {
            $result.has_urgency_levels = $true
        }

        # Count sections
        $sectionCount = 0
        if ($result.has_vehicle_info) { $sectionCount++ }
        if ($result.has_engine_ecu_info) { $sectionCount++ }
        if ($result.has_engine_dtcs) { $sectionCount++ }
        if ($result.has_parameter_analysis) { $sectionCount++ }
        if ($result.has_body_dtcs) { $sectionCount++ }
        if ($result.has_overall_assessment) { $sectionCount++ }
        $result.section_count = $sectionCount
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Sections: $($result.section_count)/6"
Write-Host "DTCs: $($result.dtc_codes_found.Count) total ($($result.engine_dtc_count) engine, $($result.body_dtc_count) body)"
Write-Host "Parameters: $($result.parameters_documented -join ', ')"
