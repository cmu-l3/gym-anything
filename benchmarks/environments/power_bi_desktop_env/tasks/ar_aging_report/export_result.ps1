# This is export_result.ps1
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting AR Aging Results ==="

# 1. Close Power BI to release file locks
Stop-Process -Name PBIDesktop -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 2. Define paths
$pbixPath = "C:\Users\Docker\Desktop\AR_Aging_Report.pbix"
$resultJson = "C:\Users\Docker\Desktop\ar_aging_result.json"
$tempDir = "C:\Users\Docker\Desktop\TempPBIX"

# 3. Initialize Result Object
$result = @{
    file_exists = $false
    file_size_bytes = 0
    visual_types = @()
    model_text_sample = ""
    layout_text_search = ""
    buckets_found = $false
    matrix_found = $false
    barchart_found = $false
}

# 4. Check File Existence
if (Test-Path $pbixPath) {
    $item = Get-Item $pbixPath
    $result.file_exists = $true
    $result.file_size_bytes = $item.Length

    # 5. Unzip .pbix (it is a zip archive) to inspect internals
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        Expand-Archive -Path $pbixPath -DestinationPath $tempDir -Force
        
        # 6. Inspect Report Layout (Visuals)
        $layoutPath = "$tempDir\Report\Layout"
        if (Test-Path $layoutPath) {
            # Layout is JSON but often encoded in UCS-2 LE BOM or similar in PBI
            $layoutContent = Get-Content $layoutPath -Raw
            
            # Simple string matching for visual types
            $result.layout_text_search = $layoutContent
            
            if ($layoutContent -match "pivotTable" -or $layoutContent -match "matrix") {
                $result.matrix_found = $true
                $result.visual_types += "matrix"
            }
            if ($layoutContent -match "clusteredBarChart") {
                $result.barchart_found = $true
                $result.visual_types += "clusteredBarChart"
            }
        }

        # 7. Inspect DataModel (Schema/Measures)
        # DataModel is binary, but strings are often visible
        $modelPath = "$tempDir\DataModel"
        if (Test-Path $modelPath) {
            # Read binary as text (lossy but sufficient for string search)
            $modelContent = Get-Content $modelPath -Encoding Latin1 -Raw
            
            # Extract a sample for python verifier to check
            # (We just store a boolean summary here to save JSON size, or keywords)
            $result.model_text_sample = "Keywords found: "
            
            $keywords = @("Days_Overdue", "Aging_Bucket", "Total_Outstanding", "1-30 Days", "31-60 Days", ">90 Days")
            foreach ($k in $keywords) {
                if ($modelContent -match $k) {
                    $result.model_text_sample += "$k, "
                }
            }
            
            # Specific bucket check
            if ($modelContent -match "1-30 Days" -and $modelContent -match ">90 Days") {
                $result.buckets_found = $true
            }
        }
    }
    catch {
        Write-Host "Error parsing PBIX: $_"
        $result.error = "$_"
    }
    
    # Cleanup
    Remove-Item $tempDir -Recurse -Force
}

# 8. Save Result JSON
$result | ConvertTo-Json -Depth 5 | Out-File $resultJson -Encoding UTF8
Write-Host "Result saved to $resultJson"