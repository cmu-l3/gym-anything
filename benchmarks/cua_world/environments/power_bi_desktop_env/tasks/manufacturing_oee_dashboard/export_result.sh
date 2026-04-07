#!/bin/bash
# Wrapper to create and run the PowerShell export script

echo "=== Generating Export Script for Windows ==="

cat << 'EOF' > /workspace/tasks/manufacturing_oee_dashboard/export_result.ps1
$ErrorActionPreference = "Continue"
Write-Output "=== Exporting Results ==="

# Define paths
$DesktopPath = "C:\Users\Docker\Desktop"
$PbixPath = "$DesktopPath\OEE_Dashboard.pbix"
$CsvPath = "$DesktopPath\machine_oee_summary.csv"
$GroundTruthPath = "C:\workspace\tasks\manufacturing_oee_dashboard\ground_truth.json"
$ResultJsonPath = "C:\workspace\tasks\manufacturing_oee_dashboard\task_result.json"
$StartTimePath = "C:\workspace\tasks\manufacturing_oee_dashboard\start_time.txt"

# 1. Close Power BI to release file locks
Stop-Process -Name "PBIDesktop" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 2. Basic File Checks
$PbixExists = Test-Path $PbixPath
$CsvExists = Test-Path $CsvPath
$PbixSize = 0
if ($PbixExists) { $PbixSize = (Get-Item $PbixPath).Length }
$CsvContent = ""
if ($CsvExists) { $CsvContent = Get-Content $CsvPath -Raw }

# 3. PBIX Inspection (Unzip and grep)
$VisualTypes = @()
$MeasureNames = @()
$LayoutFound = $false

if ($PbixExists) {
    $TempExtractPath = "$DesktopPath\TempExtract"
    if (Test-Path $TempExtractPath) { Remove-Item $TempExtractPath -Recurse -Force }
    New-Item -ItemType Directory -Path $TempExtractPath | Out-Null
    
    # Unzip
    try {
        Expand-Archive -Path $PbixPath -DestinationPath $TempExtractPath -Force
    } catch {
        Write-Output "Failed to unzip PBIX: $_"
    }
    
    # Check Layout
    $LayoutPath = "$TempExtractPath\Report\Layout"
    if (Test-Path $LayoutPath) {
        $LayoutFound = $true
        $LayoutContent = Get-Content $LayoutPath -Raw -Encoding Unicode
        # Simple string search for visual types
        if ($LayoutContent -match "gaugeChart") { $VisualTypes += "gaugeChart" }
        if ($LayoutContent -match "pivotTable") { $VisualTypes += "pivotTable" } # Matrix usually appears as pivotTable
    }
    
    # Check DataModel (Binary search for strings)
    $DataModelPath = "$TempExtractPath\DataModel"
    if (Test-Path $DataModelPath) {
        # Read binary as string is messy but often works for finding names
        # Alternative: strings command if available, or just partial byte read
        # Simple approach: Read file, convert to string (lossy), search
        $Bytes = Get-Content $DataModelPath -Encoding Byte -ReadCount 0
        $StringData = [System.Text.Encoding]::ASCII.GetString($Bytes)
        # Search for measure names (Power BI stores them in DataModel)
        $RequiredMeasures = @("Availability_Pct", "Quality_Pct", "Performance_Pct", "OEE_Score")
        foreach ($m in $RequiredMeasures) {
            if ($StringData -match $m) {
                $MeasureNames += $m
            }
        }
    }
    
    # Cleanup
    Remove-Item $TempExtractPath -Recurse -Force
}

# 4. Ground Truth
$GroundTruthJson = "{}"
if (Test-Path $GroundTruthPath) {
    $GroundTruthJson = Get-Content $GroundTruthPath -Raw
}

# 5. Timestamp Check
$StartTime = 0
if (Test-Path $StartTimePath) { $StartTime = Get-Content $StartTimePath }
$FileCreatedAfterStart = $false
if ($PbixExists) {
    $CreationTime = [int][double]::Parse((Get-Date (Get-Item $PbixPath).CreationTime -UFormat %s))
    if ($CreationTime -gt $StartTime) { $FileCreatedAfterStart = $true }
}

# 6. Construct Result JSON
$ResultObject = @{
    pbix_exists = $PbixExists
    pbix_size_bytes = $PbixSize
    csv_exists = $CsvExists
    csv_content = $CsvContent
    visual_types_found = $VisualTypes
    measures_found = $MeasureNames
    ground_truth = $GroundTruthJson
    file_created_after_start = $FileCreatedAfterStart
}

$ResultObject | ConvertTo-Json -Depth 5 | Out-File $ResultJsonPath -Encoding UTF8

Write-Output "Export Complete. Result saved to $ResultJsonPath"
EOF

# Execute
powershell -ExecutionPolicy Bypass -File /workspace/tasks/manufacturing_oee_dashboard/export_result.ps1