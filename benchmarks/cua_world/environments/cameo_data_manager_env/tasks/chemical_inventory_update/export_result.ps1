Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting chemical_inventory_update Result ==="

# Load task start timestamp
$task_start = [datetime]::MinValue
$ts_file = "C:\Windows\Temp\chemical_inventory_update_start.txt"
if (Test-Path $ts_file) {
    try {
        $task_start = [datetime]::Parse((Get-Content $ts_file -Raw).Trim())
        Write-Host "Task start: $task_start"
    } catch {
        Write-Host "WARNING: Could not parse task start timestamp"
    }
}

# Check for expected export XML file
$export_xml_path = "C:\Users\Docker\Documents\CAMEO\green_valley_2024.xml"
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
$xml_contains_green_valley = $false
$xml_contains_sodium_hypochlorite = $false
$xml_contains_7681 = $false
$xml_readable = $false

if ($export_xml_exists -and $export_xml_size -gt 100) {
    try {
        $xml_content = Get-Content $export_xml_path -Raw -ErrorAction Stop
        $xml_contains_green_valley = $xml_content -like "*Green Valley*"
        $xml_contains_sodium_hypochlorite = $xml_content -like "*Sodium Hypochlorite*"
        $xml_contains_7681 = $xml_content -like "*7681-52-9*"
        $xml_readable = $true
        Write-Host "Content checks: green_valley=$xml_contains_green_valley, NaOCl=$xml_contains_sodium_hypochlorite, CAS7681=$xml_contains_7681"
    } catch {
        Write-Host "WARNING: Could not read export XML: $_"
    }
}

# Build result JSON
$result = @{
    task_name = "chemical_inventory_update"
    task_start = $task_start.ToString("o")
    export_xml_path = $export_xml_path
    export_xml_exists = $export_xml_exists
    export_xml_is_new = $export_xml_is_new
    export_xml_size = $export_xml_size
    export_xml_readable = $xml_readable
    xml_contains_green_valley = $xml_contains_green_valley
    xml_contains_sodium_hypochlorite = $xml_contains_sodium_hypochlorite
    xml_contains_cas_7681_52_9 = $xml_contains_7681
}

$result_json = $result | ConvertTo-Json -Depth 5
$result_path = "C:\Windows\Temp\chemical_inventory_update_result.json"
$result_json | Out-File $result_path -Encoding utf8
Write-Host "Result JSON saved to: $result_path"

Write-Host "=== Export Complete ==="
