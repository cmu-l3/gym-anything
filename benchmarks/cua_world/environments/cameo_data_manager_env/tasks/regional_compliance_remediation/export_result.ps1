Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting regional_compliance_remediation Result ==="

# Load task start timestamp
$task_start = [datetime]::MinValue
$ts_file = "C:\Windows\Temp\regional_compliance_start.txt"
if (Test-Path $ts_file) {
    try {
        $task_start = [datetime]::Parse((Get-Content $ts_file -Raw).Trim())
        Write-Host "Task start: $task_start"
    } catch {
        Write-Host "WARNING: Could not parse task start timestamp"
    }
}

# Check for expected export XML file
$export_xml_path = "C:\Users\Docker\Documents\CAMEO\regional_compliance_2025.xml"
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
$xml_contains_greenfield = $false
$xml_contains_riverside = $false
$xml_contains_callahan = $false
$xml_contains_methanol = $false
$xml_contains_secondary_containment = $false
$xml_contains_station12 = $false
$xml_contains_burlington = $false
$xml_readable = $false

if ($export_xml_exists -and $export_xml_size -gt 100) {
    try {
        $xml_content = Get-Content $export_xml_path -Raw -ErrorAction Stop
        $xml_contains_greenfield = $xml_content -like "*Greenfield Operations*"
        $xml_contains_riverside = $xml_content -like "*Riverside Water Treatment*"
        $xml_contains_callahan = $xml_content -like "*Callahan*"
        $xml_contains_methanol = $xml_content -like "*Methanol*"
        $xml_contains_secondary_containment = $xml_content -like "*Secondary Containment Building*"
        $xml_contains_station12 = ($xml_content -like "*Station 12*") -or ($xml_content -like "*Montpelier Central*")
        $xml_contains_burlington = ($xml_content -like "*Burlington Fire Station*") -or ($xml_content -like "*Burlington*Downtown*")
        $xml_readable = $true
        Write-Host "Quick content checks:"
        Write-Host "  greenfield=$xml_contains_greenfield, riverside=$xml_contains_riverside"
        Write-Host "  callahan=$xml_contains_callahan, methanol=$xml_contains_methanol"
        Write-Host "  secondary_containment=$xml_contains_secondary_containment"
        Write-Host "  station12=$xml_contains_station12, burlington=$xml_contains_burlington"
    } catch {
        Write-Host "WARNING: Could not read export XML: $_"
    }
}

# Also scan for any new XML files in CAMEO docs (agent may have used a different filename)
$new_xml_files_in_cameo_docs = @()
if (Test-Path "C:\Users\Docker\Documents\CAMEO") {
    Get-ChildItem "C:\Users\Docker\Documents\CAMEO\*.xml" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.LastWriteTime -gt $task_start) {
            $new_xml_files_in_cameo_docs += $_.Name
        }
    }
}

# Build result JSON
$result = @{
    task_name = "regional_compliance_remediation"
    task_start = $task_start.ToString("o")
    export_xml_path = $export_xml_path
    export_xml_exists = $export_xml_exists
    export_xml_is_new = $export_xml_is_new
    export_xml_size = $export_xml_size
    export_xml_readable = $xml_readable
    xml_contains_greenfield = $xml_contains_greenfield
    xml_contains_riverside = $xml_contains_riverside
    xml_contains_callahan = $xml_contains_callahan
    xml_contains_methanol = $xml_contains_methanol
    xml_contains_secondary_containment = $xml_contains_secondary_containment
    xml_contains_station12 = $xml_contains_station12
    xml_contains_burlington_fire = $xml_contains_burlington
    new_xml_files_in_cameo_docs = $new_xml_files_in_cameo_docs
}

$result_json = $result | ConvertTo-Json -Depth 5
$result_path = "C:\Windows\Temp\regional_compliance_result.json"
$result_json | Out-File $result_path -Encoding utf8
Write-Host "Result JSON saved to: $result_path"

Write-Host "=== Export Complete ==="
