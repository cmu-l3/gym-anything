Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting ehs_chemical_correction Result ==="

# Load task start timestamp
$task_start = [datetime]::MinValue
$ts_file = "C:\Windows\Temp\ehs_chemical_correction_start.txt"
if (Test-Path $ts_file) {
    try {
        $task_start = [datetime]::Parse((Get-Content $ts_file -Raw).Trim())
        Write-Host "Task start: $task_start"
    } catch {
        Write-Host "WARNING: Could not parse task start timestamp"
    }
}

# Check for expected export XML file
$export_xml_path = "C:\Users\Docker\Documents\CAMEO\ehs_corrected.xml"
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

# Scan Documents\CAMEO for all XML files modified after task start
$cameo_docs_dir = "C:\Users\Docker\Documents\CAMEO"
$all_xml_files = @()
if (Test-Path $cameo_docs_dir) {
    $all_xml_files = Get-ChildItem $cameo_docs_dir -Filter "*.xml" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $task_start } |
        Select-Object -ExpandProperty Name
}
Write-Host "New XML files since task start: $($all_xml_files -join ', ')"

# Try to read the export XML content for quick validation
$xml_contains_northfield = $false
$xml_contains_essex = $false
$xml_readable = $false

if ($export_xml_exists -and $export_xml_size -gt 100) {
    try {
        $xml_content = Get-Content $export_xml_path -Raw -ErrorAction Stop
        $xml_contains_northfield = $xml_content -like "*Northfield Paper Mill*"
        $xml_contains_essex = $xml_content -like "*Essex Wire*"
        $xml_readable = $true
        Write-Host "XML content check: northfield=$xml_contains_northfield, essex=$xml_contains_essex"
    } catch {
        Write-Host "WARNING: Could not read export XML content: $_"
    }
}

# Build result JSON
$result = @{
    task_name = "ehs_chemical_correction"
    task_start = $task_start.ToString("o")
    export_xml_path = $export_xml_path
    export_xml_exists = $export_xml_exists
    export_xml_is_new = $export_xml_is_new
    export_xml_size = $export_xml_size
    export_xml_readable = $xml_readable
    xml_contains_northfield_paper_mill = $xml_contains_northfield
    xml_contains_essex_wire = $xml_contains_essex
    new_xml_files_in_cameo_docs = $all_xml_files
}

$result_json = $result | ConvertTo-Json -Depth 5
$result_path = "C:\Windows\Temp\ehs_chemical_correction_result.json"
$result_json | Out-File $result_path -Encoding utf8
Write-Host "Result JSON saved to: $result_path"

Write-Host "=== Export Complete ==="
