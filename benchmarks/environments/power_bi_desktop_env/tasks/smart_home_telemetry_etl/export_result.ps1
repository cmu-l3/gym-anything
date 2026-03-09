# PowerShell script for export_result.ps1

$ErrorActionPreference = "Continue"
Write-Host "=== Exporting Smart Home Task Results ==="

# 1. Close Power BI to release file locks
Get-Process "PBIDesktop" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 2. Define Paths
$DesktopPath = "C:\Users\Docker\Desktop"
$PbiFile = "$DesktopPath\Smart_Home_Report.pbix"
$ResultJson = "$env:TEMP\task_result.json"
$ExtractDir = "$env:TEMP\pbi_extract"

# 3. Check File Existence & Timestamp
$FileExists = $false
$FileCreatedDuringTask = $false
$FileSize = 0
$TaskStart = 0

if (Test-Path "$env:TEMP\task_start_time.txt") {
    $TaskStart = [int64](Get-Content "$env:TEMP\task_start_time.txt")
}

if (Test-Path $PbiFile) {
    $FileExists = $true
    $Item = Get-Item $PbiFile
    $FileSize = $Item.Length
    
    # Check creation/mod time
    $ModTime = [DateTimeOffset]::new($Item.LastWriteTime).ToUnixTimeSeconds()
    if ($ModTime -gt $TaskStart) {
        $FileCreatedDuringTask = $true
    }
}

# 4. Extract PBIX (It's a ZIP file) to analyze internals
$ColumnsFound = @()
$VisualsFound = @()
$ModelSchemaFound = $false

if ($FileExists -and $FileSize -gt 0) {
    if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    
    try {
        Expand-Archive -Path $PbiFile -DestinationPath $ExtractDir -Force
        
        # Analyze Report/Layout (JSON)
        $LayoutPath = "$ExtractDir\Report\Layout"
        if (Test-Path $LayoutPath) {
            # Fix encoding issues by reading as bytes or specified encoding
            $LayoutJson = Get-Content $LayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
            
            # Extract visual types
            $Sections = $LayoutJson.sections
            foreach ($section in $Sections) {
                foreach ($vc in $section.visualContainers) {
                    try {
                        $config = $vc.config | ConvertFrom-Json
                        $vType = $config.singleVisual.visualType
                        if ($vType) { $VisualsFound += $vType }
                        
                        # Check projections (what fields are used)
                        $projections = $config.singleVisual.projections
                        if ($projections) {
                            # Add flattened projections to list for debug
                            $VisualsFound += "Proj:$($projections | ConvertTo-Json -Depth 1 -Compress)"
                        }
                    } catch {}
                }
            }
        }
        
        # Analyze DataModelSchema (JSON) - Best source for columns
        $SchemaPath = "$ExtractDir\DataModelSchema"
        if (Test-Path $SchemaPath) {
            $ModelSchemaFound = $true
            # DataModelSchema is UTF-16 LE usually
            $SchemaJson = Get-Content $SchemaPath -Raw -Encoding Unicode | ConvertFrom-Json
            
            # Navigate tables -> columns
            foreach ($table in $SchemaJson.model.tables) {
                # Skip hidden/system tables
                if (-not $table.isHidden) {
                    foreach ($col in $table.columns) {
                        $ColumnsFound += $col.name
                    }
                }
            }
        }
        
    } catch {
        Write-Warning "Failed to extract or parse PBIX: $_"
    }
}

# 5. Take Final Screenshot
try {
    python -c "import pyautogui; pyautogui.screenshot(r'C:\Windows\Temp\task_final.png')"
} catch {}

# 6. Create Result JSON
$Result = @{
    task_start = $TaskStart
    output_exists = $FileExists
    file_created_during_task = $FileCreatedDuringTask
    output_size_bytes = $FileSize
    columns_found = $ColumnsFound
    visuals_found = $VisualsFound
    model_schema_found = $ModelSchemaFound
    screenshot_path = "C:\Windows\Temp\task_final.png"
}

$Result | ConvertTo-Json -Depth 5 | Set-Content $ResultJson
Write-Host "Result saved to $ResultJson"