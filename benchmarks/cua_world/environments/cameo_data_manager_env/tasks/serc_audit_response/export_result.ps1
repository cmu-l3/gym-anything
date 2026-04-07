Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting serc_audit_response Result ==="

# Load task start timestamp
$task_start = [datetime]::MinValue
$ts_file = "C:\Windows\Temp\serc_audit_response_start.txt"
if (Test-Path $ts_file) {
    try {
        $task_start = [datetime]::Parse((Get-Content $ts_file -Raw).Trim())
        Write-Host "Task start: $task_start"
    } catch {
        Write-Host "WARNING: Could not parse task start timestamp"
    }
}

# Check for expected export XML file
$export_xml_path = "C:\Users\Docker\Documents\CAMEO\lakeside_corrected.xml"
$export_xml_exists = Test-Path $export_xml_path
$export_xml_is_new = $false
$export_xml_size = 0

if ($export_xml_exists) {
    $file_info = Get-Item $export_xml_path
    $export_xml_size = $file_info.Length
    $export_xml_is_new = ($file_info.LastWriteTime -gt $task_start)
    Write-Host "Export XML found: size=$export_xml_size, modified=$($file_info.LastWriteTime), is_new=$export_xml_is_new"
} else {
    Write-Host "Export XML NOT found at: $export_xml_path"
}

# Quick content checks
$xml_contains_lakeside = $false
$xml_contains_okonkwo = $false
$xml_contains_drum_storage = $false
$xml_contains_station12 = $false
$xml_readable = $false

if ($export_xml_exists -and $export_xml_size -gt 100) {
    try {
        $xml_content = Get-Content $export_xml_path -Raw -ErrorAction Stop
        $xml_contains_lakeside = $xml_content -like "*Lakeside Chemical*"
        $xml_contains_okonkwo = $xml_content -like "*Okonkwo*"
        $xml_contains_drum_storage = $xml_content -like "*Drum Storage Building B*"
        $xml_contains_station12 = ($xml_content -like "*Station 12*") -or ($xml_content -like "*Montpelier Central*")
        $xml_readable = $true
        Write-Host "Quick content checks: lakeside=$xml_contains_lakeside, okonkwo=$xml_contains_okonkwo, drum_storage=$xml_contains_drum_storage, station12=$xml_contains_station12"
    } catch {
        Write-Host "WARNING: Could not read export XML: $_"
    }
}

# Build result JSON
$result = @{
    task_name = "serc_audit_response"
    task_start = $task_start.ToString("o")
    export_xml_path = $export_xml_path
    export_xml_exists = $export_xml_exists
    export_xml_is_new = $export_xml_is_new
    export_xml_size = $export_xml_size
    export_xml_readable = $xml_readable
    xml_contains_lakeside_chemical = $xml_contains_lakeside
    xml_contains_okonkwo = $xml_contains_okonkwo
    xml_contains_drum_storage_building_b = $xml_contains_drum_storage
    xml_contains_station_12 = $xml_contains_station12
}

$result_json = $result | ConvertTo-Json -Depth 5
$result_path = "C:\Windows\Temp\serc_audit_response_result.json"
$result_json | Out-File $result_path -Encoding utf8
Write-Host "Result JSON saved to: $result_path"

Write-Host "=== Export Complete ==="
