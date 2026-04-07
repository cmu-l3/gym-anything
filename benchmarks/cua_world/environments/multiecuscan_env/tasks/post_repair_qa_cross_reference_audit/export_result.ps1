Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting post_repair_qa_cross_reference_audit results ==="

$resultJson = "C:\Users\Docker\post_repair_qa_cross_reference_audit_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\qa_verification_report.txt"
$tsFile     = "C:\Users\Docker\Desktop\MultiecuscanTasks\post_repair_qa_cross_reference_audit_start_timestamp.txt"

$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

Start-Sleep -Seconds 3

Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$result = @{
    task_name                       = "post_repair_qa_cross_reference_audit"
    start_timestamp                 = $startTimestamp
    report_exists                   = $false
    report_file_size                = 0
    report_file_mtime               = 0
    report_content                  = ""
    # ECU system coverage
    has_engine_ecu_section          = $false
    has_body_computer_section       = $false
    both_systems_covered            = $false
    # ECU identification
    has_ecu_identification          = $false
    has_hw_sw_versions              = $false
    # DTC findings
    has_dtc_section                 = $false
    all_dtcs_found                  = @()
    # Cross-reference evidence
    has_csv_dtc_descriptions        = $false
    has_csv_parameter_ranges        = $false
    has_csv_vehicle_specs           = $false
    csv_cross_reference_count       = 0
    # Parameter comparison
    has_parameter_table             = $false
    parameter_names_found           = @()
    has_normal_range_values         = $false
    # Vehicle identification
    vehicle_id_present              = $false
    has_engine_code_mention         = $false
    # QA verdict
    has_qa_verdict                  = $false
    qa_verdict_value                = ""
    has_verdict_reasoning           = $false
    # Repair assessment
    has_turbo_assessment            = $false
    has_reflash_assessment          = $false
}

if (Test-Path $reportFile) {
    $fileInfo = Get-Item $reportFile
    $result.report_exists    = $true
    $result.report_file_size = $fileInfo.Length
    $result.report_file_mtime = [int][double]::Parse(
        (Get-Date $fileInfo.LastWriteTimeUtc -UFormat %s))

    $raw = Get-Content $reportFile -Raw -ErrorAction SilentlyContinue
    if ($raw) {
        if ($raw.Length -gt 80000) { $raw = $raw.Substring(0, 80000) }
        $result.report_content = $raw

        # -- Vehicle identification --
        if ($raw -match "(?i)(Ducato|F1AE3481|ZFA250|BD17|156[,.]?830)") {
            $result.vehicle_id_present = $true
        }
        if ($raw -match "(?i)(F1AE3481D|F1AE3481)") {
            $result.has_engine_code_mention = $true
        }

        # -- Engine ECU section --
        if ($raw -match "(?i)(Engine\s*(ECU|Control|Module)|EDC1[67]|Bosch\s*EDC|engine\s*findings)") {
            $result.has_engine_ecu_section = $true
        }

        # -- Body Computer section --
        if ($raw -match "(?i)(Body\s*(Computer|Module)|BSI|BCM|Delphi|body\s*findings)") {
            $result.has_body_computer_section = $true
        }

        $result.both_systems_covered = (
            $result.has_engine_ecu_section -and $result.has_body_computer_section)

        # -- ECU identification (part numbers, HW/SW) --
        if ($raw -match "(?i)(Part\s*Number|Drawing\s*Number|ECU\s*(ID|Ident)|ISO\s*Code)") {
            $result.has_ecu_identification = $true
        }
        if ($raw -match "(?i)(Hardware\s*(Version|Rev|:|#)|Software\s*(Version|Rev|:|#)|HW\s*[:]\s*\d|SW\s*[:]\s*\d)") {
            $result.has_hw_sw_versions = $true
        }

        # -- DTC section --
        if ($raw -match "(?i)(DTC|fault\s*code|diagnostic\s*trouble|error\s*code|stored\s*code)") {
            $result.has_dtc_section = $true
        }
        $dtcMatches = [regex]::Matches($raw, "[PBCU][01]\d{3}")
        $allDtcs = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $allDtcs) { $allDtcs += $m.Value }
        }
        $result.all_dtcs_found = $allDtcs

        # -- Cross-reference: DTC descriptions from CSV --
        # Evidence: DTC code followed by a multi-word description (not just the code alone)
        if ($raw -match "(?i)[PBCU][01]\d{3}[^a-zA-Z]{0,10}(Short|Open|Circuit|Sensor|Voltage|Signal|Range|Performance|Malfunction|Relay|Battery|Power|Energized|De-energized|Insufficient|Excessive|Low|High)") {
            $result.has_csv_dtc_descriptions = $true
        }

        # -- Cross-reference: Parameter normal ranges from CSV --
        # Evidence: presence of specific numeric ranges that match obd2_parameter_reference.csv
        # Normal_Idle_Min/Max values from the CSV: 13.5-14.5 (battery), 650-900 (RPM),
        # 80-100 (coolant), 2-8 (MAF), 10-20 (throttle), etc.
        if ($raw -match "(?i)(Normal_Idle|normal\s*range|specification\s*range|idle\s*range|min.*max|Normal\s*:\s*\d)") {
            $result.has_csv_parameter_ranges = $true
        }

        # -- Cross-reference: Vehicle specs from CSV --
        if ($raw -match "(?i)(fiat_vehicle_specs|vehicle\s*spec|spec.*verif|Euro\s*[56]|2286\s*cc|2287\s*cc|EDC17C49|EDC17C69|EDC16C39)") {
            $result.has_csv_vehicle_specs = $true
        }

        $csvCount = 0
        if ($result.has_csv_dtc_descriptions) { $csvCount++ }
        if ($result.has_csv_parameter_ranges) { $csvCount++ }
        if ($result.has_csv_vehicle_specs)    { $csvCount++ }
        $result.csv_cross_reference_count = $csvCount

        # -- Parameter comparison table --
        if ($raw -match "(?i)(parameter.*comparison|comparison.*table|observed.*normal|observed.*range|parameter.*value.*range|parameter.*table)") {
            $result.has_parameter_table = $true
        }

        # Check which parameters are mentioned
        $params = @()
        if ($raw -match "(?i)(battery\s*voltage|control\s*module\s*voltage|supply\s*voltage)") { $params += "battery_voltage" }
        if ($raw -match "(?i)(coolant\s*temp|engine\s*coolant)") { $params += "coolant_temp" }
        if ($raw -match "(?i)(engine\s*RPM|engine\s*speed|idle\s*speed)") { $params += "rpm" }
        if ($raw -match "(?i)(throttle\s*pos|throttle\s*%)") { $params += "throttle" }
        if ($raw -match "(?i)(MAF|mass\s*air\s*flow|air\s*flow\s*rate|intake\s*air\s*quantity)") { $params += "maf" }
        if ($raw -match "(?i)(fuel\s*pressure|rail\s*pressure|MPROP)") { $params += "fuel_pressure" }
        if ($raw -match "(?i)(EGR|exhaust\s*gas\s*recirculation)") { $params += "egr" }
        if ($raw -match "(?i)(intake\s*air\s*temp|IAT|intake\s*temp)") { $params += "intake_air_temp" }
        if ($raw -match "(?i)(boost\s*pressure|manifold\s*pressure|MAP)") { $params += "boost_pressure" }
        if ($raw -match "(?i)(fuel\s*trim|STFT|LTFT)") { $params += "fuel_trim" }
        if ($raw -match "(?i)(engine\s*load|calculated\s*load)") { $params += "engine_load" }
        if ($raw -match "(?i)(injection|injector)") { $params += "injection" }
        $result.parameter_names_found = $params

        # Normal range values present (specific numbers from the CSV)
        if ($raw -match "(?i)(13\.5|14\.5|650.{0,5}900|80.{0,5}100|Normal_Idle_M)") {
            $result.has_normal_range_values = $true
        }

        # -- QA verdict --
        if ($raw -match "(?i)(QA\s*Verdict|Quality\s*Assurance\s*Verdict|Final\s*Verdict|Verdict\s*:)") {
            $result.has_qa_verdict = $true
        }
        if ($raw -match "(?i)PASSED") {
            $result.qa_verdict_value = "PASSED"
        }
        if ($raw -match "(?i)CONDITIONAL\s*PASS") {
            $result.qa_verdict_value = "CONDITIONAL PASS"
        }
        if ($raw -match "(?i)FAILED") {
            $result.qa_verdict_value = "FAILED"
        }

        # Verdict reasoning
        if ($raw -match "(?i)(reason|because|based\s*on|assessment|conclusion|evidence\s*suggest|finding)") {
            $result.has_verdict_reasoning = $true
        }

        # -- Repair assessment --
        if ($raw -match "(?i)(turbo|VGT|actuator|overboost|P0234|turbo.*repair|repair.*turbo)") {
            $result.has_turbo_assessment = $true
        }
        if ($raw -match "(?i)(reflash|body\s*computer.*update|software\s*update|calibration|TSB|CAN\s*gateway|U0100)") {
            $result.has_reflash_assessment = $true
        }
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Report exists: $($result.report_exists)"
Write-Host "Both systems covered: $($result.both_systems_covered)"
Write-Host "CSV cross-references: $($result.csv_cross_reference_count)/3"
Write-Host "Parameters found: $($result.parameter_names_found -join ', ')"
Write-Host "QA verdict: $($result.qa_verdict_value)"
Write-Host "All DTCs: $($result.all_dtcs_found -join ', ')"
