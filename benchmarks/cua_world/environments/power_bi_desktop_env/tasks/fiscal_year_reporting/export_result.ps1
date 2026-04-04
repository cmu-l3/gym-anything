# Content for C:\workspace\tasks\fiscal_year_reporting\export_result.ps1

<file name="export_result.ps1">
$ErrorActionPreference = "Continue"
Write-Host "=== Exporting Results ==="

# 1. Close Power BI to release file locks (needed for unzip/inspection)
Stop-Process -Name "PBIDesktop" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 2. Paths
$desktopPath = "C:\Users\Docker\Desktop"
$pbixPath = "$desktopPath\Fiscal_Report.pbix"
$resultJsonPath = "$desktopPath\fiscal_result.json"
$startTimeFile = "$desktopPath\task_start_time.txt"

# 3. Initialize Result Object
$result = @{
    file_exists = $false
    file_size_bytes = 0
    file_created_after_start = $false
    contains_datesytd = $false
    contains_year_end_param = $false
    contains_sort_column_logic = $false
    model_strings_found = @()
}

# 4. Check File Existence & Timestamp
if (Test-Path $pbixPath) {
    $item = Get-Item $pbixPath
    $result.file_exists = $true
    $result.file_size_bytes = $item.Length
    
    if (Test-Path $startTimeFile) {
        $startUnix = Get-Content $startTimeFile
        $creationUnix = $item.CreationTime.ToUnixTimeSeconds()
        $writeUnix = $item.LastWriteTime.ToUnixTimeSeconds()
        
        if ($writeUnix -gt $startUnix) {
            $result.file_created_after_start = $true
        }
    }
    
    # 5. Inspect PBIX Content (It's a ZIP file)
    # We rename to .zip, extract DataModel, and search for strings
    $zipPath = "$desktopPath\temp_verify.zip"
    $extractPath = "$desktopPath\temp_verify_extract"
    
    Copy-Item $pbixPath $zipPath
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        
        # Search DataModel file (binary) for DAX strings
        # Note: This is a heuristic search in the binary file
        $dataModelFile = "$extractPath\DataModel"
        if (Test-Path $dataModelFile) {
            $bytes = Get-Content $dataModelFile -Encoding Byte -Raw
            # Convert to string (lossy, but good enough for ASCII keyword search)
            $content = [System.Text.Encoding]::ASCII.GetString($bytes)
            
            # Check for DATESYTD and "03-31" or "3/31"
            if ($content -match "DATESYTD") { $result.contains_datesytd = $true }
            if ($content -match "03-31" -or $content -match "31-03" -or $content -match "3/31") { 
                $result.contains_year_end_param = $true 
            }
            
            # Check for indications of sort column usage or column naming
            # "Fiscal_Sort" or "SortBy" might appear in the model schema
            if ($content -match "Sort" -and ($content -match "Index" -or $content -match "Order")) {
                $result.contains_sort_column_logic = $true
            }
            
            # Log exact strings for debugging
            if ($content -match "Fiscal_YTD") { $result.model_strings_found += "Fiscal_YTD" }
        }
    }
    catch {
        Write-Host "Error analyzing PBIX structure: $_"
    }
    
    # Cleanup
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}

# 6. Save Result
$result | ConvertTo-Json | Out-File $resultJsonPath -Encoding utf8
Write-Host "Results saved to $resultJsonPath"
</file>