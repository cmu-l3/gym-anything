Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting new_facility_onboarding Result ==="

# Load task start timestamp
$task_start = [datetime]::MinValue
$ts_file = "C:\Windows\Temp\new_facility_onboarding_start.txt"
if (Test-Path $ts_file) {
    try {
        $task_start = [datetime]::Parse((Get-Content $ts_file -Raw).Trim())
        Write-Host "Task start: $task_start"
    } catch {
        Write-Host "WARNING: Could not parse task start timestamp"
    }
}

# Check for expected export XML file
$export_xml_path = "C:\Users\Docker\Documents\CAMEO\new_facilities.xml"
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
$xml_contains_champlain = $false
$xml_contains_essex_chemical = $false
$xml_contains_kowalski = $false
$xml_contains_obrecht = $false
$xml_contains_burlington_station3 = $false
$xml_contains_essex_district1 = $false
$xml_readable = $false

if ($export_xml_exists -and $export_xml_size -gt 100) {
    try {
        $xml_content = Get-Content $export_xml_path -Raw -ErrorAction Stop
        $xml_contains_champlain = $xml_content -like "*Champlain Plastics*"
        $xml_contains_essex_chemical = $xml_content -like "*Essex Chemical*"
        $xml_contains_kowalski = $xml_content -like "*Kowalski*"
        $xml_contains_obrecht = $xml_content -like "*Obrecht*"
        $xml_contains_burlington_station3 = ($xml_content -like "*Burlington Central*") -or ($xml_content -like "*Fire Station 3*")
        $xml_contains_essex_district1 = $xml_content -like "*Essex Fire District 1*"
        $xml_readable = $true
        Write-Host "Quick checks: champlain=$xml_contains_champlain, essex_chem=$xml_contains_essex_chemical, kowalski=$xml_contains_kowalski, obrecht=$xml_contains_obrecht"
        Write-Host "  burlington_station3=$xml_contains_burlington_station3, essex_district1=$xml_contains_essex_district1"
    } catch {
        Write-Host "WARNING: Could not read export XML: $_"
    }
}

# Build result JSON
$result = @{
    task_name = "new_facility_onboarding"
    task_start = $task_start.ToString("o")
    export_xml_path = $export_xml_path
    export_xml_exists = $export_xml_exists
    export_xml_is_new = $export_xml_is_new
    export_xml_size = $export_xml_size
    export_xml_readable = $xml_readable
    xml_contains_champlain_plastics = $xml_contains_champlain
    xml_contains_essex_chemical = $xml_contains_essex_chemical
    xml_contains_kowalski = $xml_contains_kowalski
    xml_contains_obrecht = $xml_contains_obrecht
    xml_contains_burlington_fire_station_3 = $xml_contains_burlington_station3
    xml_contains_essex_fire_district_1 = $xml_contains_essex_district1
}

$result_json = $result | ConvertTo-Json -Depth 5
$result_path = "C:\Windows\Temp\new_facility_onboarding_result.json"
$result_json | Out-File $result_path -Encoding utf8
Write-Host "Result JSON saved to: $result_path"

Write-Host "=== Export Complete ==="
