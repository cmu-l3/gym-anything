Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting multi_system_scan results ==="

$resultJson = "C:\Users\Docker\Desktop\MultiecuscanTasks\multi_system_scan_result.json"
$reportFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\multi_system_report.txt"
$tsFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\multi_system_scan_start_timestamp.txt"

$startTimestamp = 0
if (Test-Path $tsFile) {
    $startTimestamp = [int](Get-Content $tsFile -Raw).Trim()
}

Start-Sleep -Seconds 3
Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$result = @{
    task_name = "multi_system_scan"
    start_timestamp = $startTimestamp
    report_exists = $false
    report_file_size = 0
    report_file_mtime = 0
    report_content = ""
    system_count = 0
    has_engine_section = $false
    has_abs_section = $false
    has_airbag_section = $false
    has_overall_summary = $false
    dtc_codes_found = @()
    ecu_identifications = 0
    system_sections = @()
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

        # Count system sections
        $sections = @()
        if ($content -match "(?i)(ENGINE|Motor|Motore)") {
            $result.has_engine_section = $true
            $sections += "Engine"
        }
        if ($content -match "(?i)(ABS|ESP|Anti.?Lock|Brake)") {
            $result.has_abs_section = $true
            $sections += "ABS"
        }
        if ($content -match "(?i)(AIRBAG|SRS|Restraint|Air\s*Bag)") {
            $result.has_airbag_section = $true
            $sections += "Airbag"
        }
        $result.system_sections = $sections
        $result.system_count = $sections.Count

        # Check for overall summary
        if ($content -match "(?i)(Overall|Summary|Health|Conclusion|Assessment)") {
            $result.has_overall_summary = $true
        }

        # Extract DTC codes
        $dtcMatches = [regex]::Matches($content, "[PBCU][01]\d{3}")
        $dtcCodes = @()
        foreach ($m in $dtcMatches) {
            if ($m.Value -notin $dtcCodes) { $dtcCodes += $m.Value }
        }
        $result.dtc_codes_found = $dtcCodes

        # Count ECU identifications (part number, HW version, SW version mentions)
        $ecuIdCount = ([regex]::Matches($content, "(?i)(Part\s*Number|Hardware|Software\s*Version|ECU\s*(ID|Info|Ident))")).Count
        $result.ecu_identifications = [math]::Min($ecuIdCount, 10)
    }
}

$jsonContent = $result | ConvertTo-Json -Depth 5
Set-Content -Path $resultJson -Value $jsonContent -Encoding UTF8

Write-Host "Result exported to: $resultJson"
Write-Host "Systems found: $($result.system_sections -join ', ')"
Write-Host "DTCs found: $($result.dtc_codes_found -join ', ')"
