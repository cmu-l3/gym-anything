Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting electrical_consumer_drain_audit results ==="

$resultJson = "C:\Users\Docker\electrical_consumer_drain_audit_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\drain_audit_report.txt"
$tsFile     = "C:\Users\Docker\Desktop\MultiecuscanTasks\electrical_consumer_drain_audit_start_timestamp.txt"

$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

Start-Sleep -Seconds 3

Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$result = @{
    task_name                   = "electrical_consumer_drain_audit"
    start_timestamp             = $startTimestamp
    report_exists               = $false
    report_file_size            = 0
    report_file_mtime           = 0
    report_content              = ""
    has_body_computer_section   = $false
    has_engine_ecu_section      = $false
    both_systems_covered        = $false
    has_dtc_section             = $false
    body_dtcs_found             = @()
    engine_dtcs_found           = @()
    all_dtcs_found              = @()
    has_battery_voltage_param   = $false
    has_can_fault_mention       = $false
    has_suspect_list            = $false
    has_next_steps              = $false
    has_fuse_test_mention       = $false
    suspect_modules             = @()
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

        # Vehicle identification
        if ($raw -match "(?i)(500L|Fiat\s*500|199B6|1368|FN15|ZFA339|52[,.]?8)") {
            $result.vehicle_id_present = $true
        }

        # Body Computer section
        if ($raw -match "(?i)(Body\s*Computer|BSI|BCM|Body\s*System|Comfort\s*Module)") {
            $result.has_body_computer_section = $true
        }

        # Engine ECU section
        if ($raw -match "(?i)(Engine\s*ECU|Engine\s*Control|199B6|engine\s*module)") {
            $result.has_engine_ecu_section = $true
        }

        $result.both_systems_covered = ($result.has_body_computer_section -and $result.has_engine_ecu_section)

        # DTC section
        if ($raw -match "(?i)(DTC|fault\s*code|diagnostic\s*trouble|error\s*code|no\s*(stored\s*)?fault)") {
            $result.has_dtc_section = $true
        }

        # Extract all DTC codes and attempt to classify by section
        $dtcMatches = [regex]::Matches($raw, "[PBCU][01]\d{3}")
        $allDtcs = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $allDtcs) { $allDtcs += $m.Value }
        }
        $result.all_dtcs_found = $allDtcs

        # Battery voltage parameter
        if ($raw -match "(?i)(battery\s*voltage|supply\s*voltage|12\.\d+\s*V|13\.\d+\s*V|14\.\d+\s*V)") {
            $result.has_battery_voltage_param = $true
        }

        # CAN bus fault mention
        if ($raw -match "(?i)(CAN\s*bus|CAN\s*fault|network\s*fault|communication\s*error|U0[01]\d{2})") {
            $result.has_can_fault_mention = $true
        }

        # Suspect list (ranked modules)
        if ($raw -match "(?i)(suspect|most\s*likely|probable\s*cause|drain\s*source|ranked|priority)") {
            $result.has_suspect_list = $true
        }

        # Which modules are suspected
        $suspects = @()
        if ($raw -match "(?i)(alarm|siren)") { $suspects += "alarm_siren" }
        if ($raw -match "(?i)(infotainment|radio|audio|multimedia)") { $suspects += "infotainment" }
        if ($raw -match "(?i)(gateway|GW\s*module)") { $suspects += "gateway" }
        if ($raw -match "(?i)(body\s*computer|BSI|BCM).*(?:staying|wake|awake|active)") { $suspects += "BSI_wake" }
        if ($raw -match "(?i)(central\s*locking|door\s*lock|TPMS)") { $suspects += "locking_TPMS" }
        if ($raw -match "(?i)(climate|HVAC|air\s*con)") { $suspects += "climate" }
        $result.suspect_modules = $suspects

        # Next steps / diagnostic procedure
        if ($raw -match "(?i)(next\s*step|recommend|procedure|action|sequence)") {
            $result.has_next_steps = $true
        }

        # Fuse pull test mention
        if ($raw -match "(?i)(fuse|current\s*clamp|milliamp|mA|ammeter|isolat)") {
            $result.has_fuse_test_mention = $true
        }
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Report exists: $($result.report_exists)"
Write-Host "Both systems covered: $($result.both_systems_covered)"
Write-Host "All DTCs: $($result.all_dtcs_found -join ', ')"
Write-Host "Suspect modules: $($result.suspect_modules -join ', ')"
