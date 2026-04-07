Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting turbo_vgt_actuator_root_cause results ==="

$resultJson = "C:\Users\Docker\turbo_vgt_actuator_root_cause_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\turbo_rca_report.txt"
$tsFile     = "C:\Users\Docker\Desktop\MultiecuscanTasks\turbo_vgt_actuator_root_cause_start_timestamp.txt"

$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

Start-Sleep -Seconds 3

Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$result = @{
    task_name                   = "turbo_vgt_actuator_root_cause"
    start_timestamp             = $startTimestamp
    report_exists               = $false
    report_file_size            = 0
    report_file_mtime           = 0
    report_content              = ""
    has_ecu_section             = $false
    has_dtc_section             = $false
    has_boost_parameters        = $false
    has_maf_parameter           = $false
    has_egr_parameter           = $false
    has_root_cause_section      = $false
    has_repair_recommendations  = $false
    turbo_dtcs_found            = @()
    all_dtc_codes_found         = @()
    root_cause_identified       = ""
    live_parameters_count       = 0
    vehicle_id_present          = $false
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
        if ($raw -match "(?i)(Punto|Multijet|1\.3|169A1|ECU|Part\s*Number|Hardware|Software)") {
            $result.has_ecu_section = $true
        }
        if ($raw -match "(?i)(Punto|1248|Multijet|ZFA199|LK12)") {
            $result.vehicle_id_present = $true
        }

        # DTC section
        if ($raw -match "(?i)(DTC|fault\s*code|diagnostic\s*trouble|error\s*code|no\s*(stored\s*)?fault)") {
            $result.has_dtc_section = $true
        }

        # Extract all DTC codes
        $dtcMatches = [regex]::Matches($raw, "[PBCU][01]\d{3}")
        $allDtcs = @(); $turboDtcs = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $allDtcs) { $allDtcs += $m.Value }
            # Turbo-related DTC ranges
            $code = $m.Value
            if ($code -match "^P0(0[3-9]\d|[12]\d{2}|23[0-9]|24[0-9]|29[0-9]|045|046)") {
                if ($code -notin $turboDtcs) { $turboDtcs += $code }
            }
        }
        $result.all_dtc_codes_found = $allDtcs
        $result.turbo_dtcs_found    = $turboDtcs

        # Live parameter monitoring
        $paramCount = 0
        if ($raw -match "(?i)(boost\s*pressure|manifold\s*pressure|MAP\s*sensor|turbo\s*pressure)") {
            $result.has_boost_parameters = $true; $paramCount++
        }
        if ($raw -match "(?i)(mass\s*air\s*flow|MAF|air\s*flow\s*meter)") {
            $result.has_maf_parameter = $true; $paramCount++
        }
        if ($raw -match "(?i)(EGR|exhaust\s*gas\s*recirculation)") {
            $result.has_egr_parameter = $true; $paramCount++
        }
        if ($raw -match "(?i)(RPM|engine\s*speed|revolution)") { $paramCount++ }
        if ($raw -match "(?i)(coolant|water\s*temp)") { $paramCount++ }
        if ($raw -match "(?i)(throttle|intake\s*position)") { $paramCount++ }
        if ($raw -match "(?i)(actuator|duty\s*cycle|solenoid)") { $paramCount++ }
        $result.live_parameters_count = $paramCount

        # Root cause section
        if ($raw -match "(?i)(root\s*cause|most\s*probable|primary\s*fault|diagnosis|conclusion|finding)") {
            $result.has_root_cause_section = $true
        }

        # Identify which root cause was named
        if ($raw -match "(?i)(actuator\s*solenoid|VGT\s*actuator|P0045|P0046)") {
            $result.root_cause_identified = "VGT_actuator_solenoid"
        } elseif ($raw -match "(?i)(stuck|carbon|fouled|VGT\s*geometry|P0234|P0299)") {
            $result.root_cause_identified = "VGT_geometry_stuck"
        } elseif ($raw -match "(?i)(boost\s*sensor|pressure\s*sensor|P0235|P0236)") {
            $result.root_cause_identified = "boost_sensor_fault"
        } elseif ($raw -match "(?i)(EGR\s*valve|recirculation|P0400|P0401|P0404)") {
            $result.root_cause_identified = "EGR_contribution"
        } elseif ($raw -match "(?i)(intercooler|pipe\s*leak|boost\s*leak|hose)") {
            $result.root_cause_identified = "intercooler_leak"
        }

        # Repair recommendations
        if ($raw -match "(?i)(recommend|repair|replace|action|service|clean|fix|part\s*number)") {
            $result.has_repair_recommendations = $true
        }
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Report exists: $($result.report_exists)"
Write-Host "Turbo DTCs: $($result.turbo_dtcs_found -join ', ')"
Write-Host "All DTCs: $($result.all_dtc_codes_found -join ', ')"
Write-Host "Root cause: $($result.root_cause_identified)"
Write-Host "Parameters count: $($result.live_parameters_count)"
