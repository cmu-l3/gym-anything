Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting body_computer_analysis results ==="

$resultJson = "C:\Users\Docker\Desktop\MultiecuscanTasks\body_computer_analysis_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\body_computer_report.txt"
$tsFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\body_computer_analysis_start_timestamp.txt"

$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

Start-Sleep -Seconds 3
Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$result = @{
    task_name = "body_computer_analysis"
    start_timestamp = $startTimestamp
    report_exists = $false
    report_file_size = 0
    report_file_mtime = 0
    report_content = ""
    has_ecu_info = $false
    has_dtc_section = $false
    has_config_section = $false
    has_recommendations = $false
    dtc_codes_found = @()
    config_items_count = 0
    config_categories = @()
    mentions_drl = $false
    mentions_door_lock = $false
    mentions_lights = $false
    mentions_seatbelt = $false
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

        # ECU info
        if ($content -match "(?i)(ECU\s*(Info|Ident)|Part\s*Number|Hardware|Software)") {
            $result.has_ecu_info = $true
        }

        # DTC section
        if ($content -match "(?i)(DTC|Error|Fault|Trouble\s*Code)") {
            $result.has_dtc_section = $true
        }
        $dtcMatches = [regex]::Matches($content, "[PBCU][01]\d{3}")
        $dtcCodes = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $dtcCodes) { $dtcCodes += $m.Value }
        }
        $result.dtc_codes_found = $dtcCodes

        # Configuration section
        if ($content -match "(?i)(Config|Adjust|Setting|PROXI|Adaptation)") {
            $result.has_config_section = $true
        }

        # Count configuration items (lines with colons or equals, typical for key:value)
        $configLines = ($content -split "`n") | Where-Object { $_ -match "^\s*.+[:\=].+" }
        $result.config_items_count = [math]::Min($configLines.Count, 100)

        # Check for specific configuration categories
        $categories = @()
        if ($content -match "(?i)(DRL|Daytime|Running\s*Light)") {
            $result.mentions_drl = $true
            $categories += "DRL"
        }
        if ($content -match "(?i)(Door\s*Lock|Auto.?Lock|Central\s*Lock)") {
            $result.mentions_door_lock = $true
            $categories += "Door_Lock"
        }
        if ($content -match "(?i)(Interior\s*Light|Courtesy|Dome\s*Light|Illumination)") {
            $result.mentions_lights = $true
            $categories += "Interior_Lights"
        }
        if ($content -match "(?i)(Seatbelt|Seat\s*Belt|Belt\s*Warning|Buckle)") {
            $result.mentions_seatbelt = $true
            $categories += "Seatbelt"
        }
        if ($content -match "(?i)(Follow.?Me|Home\s*Light|Headlight\s*Delay)") {
            $categories += "Follow_Me_Home"
        }
        if ($content -match "(?i)(Key\s*Fob|Remote|Window\s*Control)") {
            $categories += "Key_Fob"
        }
        if ($content -match "(?i)(Turn\s*Signal|Indicator|Flash\s*Count)") {
            $categories += "Turn_Signals"
        }
        if ($content -match "(?i)(Rain\s*Sensor|Wiper)") {
            $categories += "Rain_Sensor"
        }
        $result.config_categories = $categories

        # Recommendations
        if ($content -match "(?i)(Recommend|Suggest|Common\s*Change|Owner|Customer|Popular)") {
            $result.has_recommendations = $true
        }
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Config categories: $($result.config_categories -join ', ')"
Write-Host "Config items: $($result.config_items_count)"
