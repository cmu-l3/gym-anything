# <file name="export_result.ps1">
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting Task Results ==="

$taskStartPath = "C:\workspace\tasks\forensic_accounting_benford\task_start_time.txt"
$taskStart = 0
if (Test-Path $taskStartPath) {
    $taskStart = Get-Content $taskStartPath | Select-Object -First 1
}

$pbiFile = "C:\Users\Docker\Desktop\Fraud_Detection.pbix"
$resultJson = "C:\Users\Docker\Desktop\task_result.json"
$tempDir = "C:\Users\Docker\AppData\Local\Temp\PBI_Extract"

# Initialize Result Object
$result = @{
    file_exists = $false
    file_created_during_task = $false
    file_size_bytes = 0
    contains_benford_measure = $false
    contains_leading_digit_column = $false
    visual_types = @()
    model_keywords_found = @()
}

# 1. Check File Existence and Timestamp
if (Test-Path $pbiFile) {
    $item = Get-Item $pbiFile
    $result.file_exists = $true
    $result.file_size_bytes = $item.Length
    
    # Check creation/write time (Unix timestamp)
    $writeTime = [DateTimeOffset]::new($item.LastWriteTime).ToUnixTimeSeconds()
    if ($writeTime -gt $taskStart) {
        $result.file_created_during_task = $true
    }
}

# 2. Inspect PBIX Content (if file exists)
if ($result.file_exists) {
    # PBIX is a zip file. Unzip to inspect Layout and DataModel
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        Expand-Archive -Path $pbiFile -DestinationPath $tempDir -Force
        
        # A. Inspect Report Layout (JSON) for Visual Types
        $layoutPath = "$tempDir\Report\Layout"
        if (Test-Path $layoutPath) {
            # Layout is often UTF-16 LE
            $layoutContent = Get-Content $layoutPath -Raw -Encoding Unicode
            
            # Simple string match for visual types
            if ($layoutContent -match "lineClusteredColumnComboChart") { $result.visual_types += "lineClusteredColumnComboChart" }
            if ($layoutContent -match "lineStackedColumnComboChart") { $result.visual_types += "lineStackedColumnComboChart" }
            if ($layoutContent -match "columnChart") { $result.visual_types += "columnChart" }
            if ($layoutContent -match "lineChart") { $result.visual_types += "lineChart" }
        }

        # B. Inspect DataModel (Binary/Text mix) for Keywords
        # We search for strings like "LOG10" or "Leading_Digit" in the unzipped content
        # Note: DataModel is binary, but strings are often preserved
        $dataModelPath = "$tempDir\DataModel"
        if (Test-Path $dataModelPath) {
            # Read as bytes, convert to string (lossy is fine for keyword search)
            $bytes = [System.IO.File]::ReadAllBytes($dataModelPath)
            $text = [System.Text.Encoding]::ASCII.GetString($bytes)
            
            # Keywords to search
            $keywords = @("LOG10", "Leading_Digit", "Benford", "Actual_Frequency", "DIVIDE")
            foreach ($kw in $keywords) {
                if ($text -match $kw) {
                    $result.model_keywords_found += $kw
                }
            }
        }
    }
    catch {
        Write-Host "Error analyzing PBIX structure: $_"
    }
}

# 3. Save Result to JSON
$result | ConvertTo-Json -Depth 5 | Out-File $resultJson -Encoding UTF8

Write-Host "Result exported to $resultJson"
Get-Content $resultJson
Write-Host "=== Export Complete ==="
# </file>