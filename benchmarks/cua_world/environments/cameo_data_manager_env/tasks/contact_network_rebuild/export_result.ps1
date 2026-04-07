Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting contact_network_rebuild Result ==="

# Load task start timestamp
$task_start = [datetime]::MinValue
$ts_file = "C:\Windows\Temp\contact_network_rebuild_start.txt"
if (Test-Path $ts_file) {
    try {
        $task_start = [datetime]::Parse((Get-Content $ts_file -Raw).Trim())
        Write-Host "Task start: $task_start"
    } catch {
        Write-Host "WARNING: Could not parse task start timestamp"
    }
}

# Check for expected export XML file
$export_xml_path = "C:\Users\Docker\Documents\CAMEO\contacts_updated.xml"
$export_xml_exists = Test-Path $export_xml_path
$export_xml_is_new = $false
$export_xml_size = 0

if ($export_xml_exists) {
    $file_info = Get-Item $export_xml_path
    $export_xml_size = $file_info.Length
    $export_xml_is_new = ($file_info.LastWriteTime -gt $task_start)
    Write-Host "Export XML found: $export_xml_path (size=$export_xml_size, modified=$($file_info.LastWriteTime), is_new=$export_xml_is_new)"
} else {
    Write-Host "Export XML NOT found at: $export_xml_path"
}

# Quick content check
$xml_contains_montpelier = $false
$xml_contains_richmond = $false
$xml_contains_flanagan = $false
$xml_contains_santos = $false
$xml_readable = $false

if ($export_xml_exists -and $export_xml_size -gt 100) {
    try {
        $xml_content = Get-Content $export_xml_path -Raw -ErrorAction Stop
        $xml_contains_montpelier = $xml_content -like "*Montpelier Industrial*"
        $xml_contains_richmond = $xml_content -like "*Richmond Processing*"
        $xml_contains_flanagan = $xml_content -like "*Flanagan*"
        $xml_contains_santos = $xml_content -like "*Santos*"
        $xml_readable = $true
        Write-Host "Quick XML checks: montpelier=$xml_contains_montpelier, richmond=$xml_contains_richmond, flanagan=$xml_contains_flanagan, santos=$xml_contains_santos"
    } catch {
        Write-Host "WARNING: Could not read export XML: $_"
    }
}

# Build result JSON
$result = @{
    task_name = "contact_network_rebuild"
    task_start = $task_start.ToString("o")
    export_xml_path = $export_xml_path
    export_xml_exists = $export_xml_exists
    export_xml_is_new = $export_xml_is_new
    export_xml_size = $export_xml_size
    export_xml_readable = $xml_readable
    xml_contains_montpelier = $xml_contains_montpelier
    xml_contains_richmond = $xml_contains_richmond
    xml_contains_flanagan = $xml_contains_flanagan
    xml_contains_santos = $xml_contains_santos
}

$result_json = $result | ConvertTo-Json -Depth 5
$result_path = "C:\Windows\Temp\contact_network_rebuild_result.json"
$result_json | Out-File $result_path -Encoding utf8
Write-Host "Result JSON saved to: $result_path"

Write-Host "=== Export Complete ==="
