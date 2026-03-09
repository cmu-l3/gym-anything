Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting engine_fault_diagnosis results ==="

$resultJson = "C:\Users\Docker\Desktop\MultiecuscanTasks\engine_fault_diagnosis_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\engine_diagnostic_report.txt"
$tsFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\engine_fault_diagnosis_start_timestamp.txt"

# Read start timestamp
$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

# Wait briefly for any final writes
Start-Sleep -Seconds 3

# Stop Multiecuscan
Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Build result JSON
$result = @{
    task_name = "engine_fault_diagnosis"
    start_timestamp = $startTimestamp
    report_exists = $false
    report_file_size = 0
    report_file_mtime = 0
    report_content = ""
    has_ecu_info_section = $false
    has_dtc_section = $false
    has_parameter_section = $false
    has_recommendations = $false
    dtc_codes_found = @()
    parameters_found = @()
    ecu_info_fields = @()
    mes_was_running = $false
}

# Check if Multiecuscan was running (check for any log/config files created during session)
$mesConfigDir = "C:\Users\Docker\AppData\Local\Multiecuscan"
$mesConfigDir2 = "C:\Users\Docker\AppData\Roaming\Multiecuscan"
if ((Test-Path $mesConfigDir) -or (Test-Path $mesConfigDir2) -or (Test-Path "C:\ProgramData\Multiecuscan")) {
    $result.mes_was_running = $true
}

# Check report file
if (Test-Path $reportFile) {
    $fileInfo = Get-Item $reportFile
    $result.report_exists = $true
    $result.report_file_size = $fileInfo.Length
    $result.report_file_mtime = [int][double]::Parse((Get-Date $fileInfo.LastWriteTimeUtc -UFormat %s))

    $content = Get-Content $reportFile -Raw -ErrorAction SilentlyContinue
    if ($content) {
        # Truncate to 50KB for JSON
        if ($content.Length -gt 50000) { $content = $content.Substring(0, 50000) }
        $result.report_content = $content

        # Check for ECU info section
        if ($content -match "(?i)(ECU\s*(Info|Identification)|Part\s*Number|Hardware\s*Version|Software\s*Version)") {
            $result.has_ecu_info_section = $true
        }
        # Extract ECU info fields
        $ecuFields = @()
        if ($content -match "(?i)Part\s*Number") { $ecuFields += "part_number" }
        if ($content -match "(?i)Hardware\s*Version") { $ecuFields += "hardware_version" }
        if ($content -match "(?i)Software\s*Version") { $ecuFields += "software_version" }
        if ($content -match "(?i)Calibration") { $ecuFields += "calibration_id" }
        $result.ecu_info_fields = $ecuFields

        # Check for DTC section
        if ($content -match "(?i)(DTC|Diagnostic\s*Trouble\s*Code|Error\s*Code|Fault\s*Code)") {
            $result.has_dtc_section = $true
        }
        # Extract DTC codes (P0xxx, P1xxx, B0xxx, C0xxx, U0xxx patterns)
        $dtcMatches = [regex]::Matches($content, "[PBCU][01]\d{3}")
        $dtcCodes = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $dtcCodes) { $dtcCodes += $m.Value }
        }
        $result.dtc_codes_found = $dtcCodes

        # Check for parameter section
        if ($content -match "(?i)(Parameter|RPM|Coolant|Battery|Throttle|Live\s*Data)") {
            $result.has_parameter_section = $true
        }
        # Extract parameters mentioned
        $params = @()
        if ($content -match "(?i)RPM") { $params += "RPM" }
        if ($content -match "(?i)Coolant") { $params += "Coolant_Temperature" }
        if ($content -match "(?i)(Battery|Voltage)") { $params += "Battery_Voltage" }
        if ($content -match "(?i)Throttle") { $params += "Throttle_Position" }
        $result.parameters_found = $params

        # Check for recommendations
        if ($content -match "(?i)(Recommend|Action|Suggest|Assessment|Conclusion)") {
            $result.has_recommendations = $true
        }
    }
}

# Write result JSON
$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Report exists: $($result.report_exists)"
Write-Host "Report size: $($result.report_file_size) bytes"
Write-Host "DTCs found: $($result.dtc_codes_found -join ', ')"
Write-Host "Parameters found: $($result.parameters_found -join ', ')"
