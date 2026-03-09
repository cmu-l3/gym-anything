Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting parameter_monitoring_export results ==="

$resultJson = "C:\Users\Docker\Desktop\MultiecuscanTasks\parameter_monitoring_export_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\parameter_analysis.txt"
$tsFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\parameter_monitoring_export_start_timestamp.txt"

$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

Start-Sleep -Seconds 3
Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$result = @{
    task_name = "parameter_monitoring_export"
    start_timestamp = $startTimestamp
    report_exists = $false
    report_file_size = 0
    report_file_mtime = 0
    report_content = ""
    has_rpm = $false
    has_coolant_temp = $false
    has_voltage = $false
    has_throttle = $false
    parameters_with_values = 0
    has_normal_ranges = $false
    has_assessment = $false
    has_real_data_comparison = $false
    has_min_max_avg = $false
    numeric_values_found = @()
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

        # Check for each parameter
        if ($content -match "(?i)RPM") { $result.has_rpm = $true }
        if ($content -match "(?i)(Coolant|Temperature|ECT)") { $result.has_coolant_temp = $true }
        if ($content -match "(?i)(Voltage|Battery|Control\s*Module)") { $result.has_voltage = $true }
        if ($content -match "(?i)(Throttle|TPS)") { $result.has_throttle = $true }

        # Count parameters with numeric values
        $paramCount = 0
        if ($result.has_rpm -and ($content -match "(?i)RPM[^0-9]*(\d+)")) { $paramCount++ }
        if ($result.has_coolant_temp -and ($content -match "(?i)(Coolant|Temp)[^0-9]*(\d+)")) { $paramCount++ }
        if ($result.has_voltage -and ($content -match "(?i)(Volt|Battery)[^0-9]*(\d+\.?\d*)")) { $paramCount++ }
        if ($result.has_throttle -and ($content -match "(?i)Throttle[^0-9]*(\d+)")) { $paramCount++ }
        $result.parameters_with_values = $paramCount

        # Check for normal range references
        if ($content -match "(?i)(Normal|Range|Nominal|Spec|Standard|Reference)") {
            $result.has_normal_ranges = $true
        }

        # Check for assessment
        if ($content -match "(?i)(OK|WARNING|CRITICAL|Within|Out\s*of|Assessment|Status|Normal|Abnormal)") {
            $result.has_assessment = $true
        }

        # Check for real data comparison
        if ($content -match "(?i)(Real|Actual|Recorded|Drive|Session|Compare|Comparison|real_obd)") {
            $result.has_real_data_comparison = $true
        }

        # Check for min/max/avg
        if ($content -match "(?i)(Min|Max|Average|Avg|Mean|Minimum|Maximum)") {
            $result.has_min_max_avg = $true
        }

        # Extract numeric values
        $nums = [regex]::Matches($content, "\d+\.?\d*\s*(rpm|°C|V|%|kPa|g/s)")
        $numericValues = @()
        foreach ($n in $nums) {
            if ($numericValues.Count -lt 20) { $numericValues += $n.Value }
        }
        $result.numeric_values_found = $numericValues
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Parameters with values: $($result.parameters_with_values)/4"
