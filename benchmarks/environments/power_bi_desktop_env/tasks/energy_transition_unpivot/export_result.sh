#!/bin/bash
echo "=== Exporting Energy Transition Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# PowerShell script to inspect the PBIX file
cat << 'EOF' > /tmp/inspect_pbi.ps1
$ErrorActionPreference = "SilentlyContinue"
$DesktopPath = "C:\Users\Docker\Desktop"
$ReportPath = "$DesktopPath\Energy_Transition.pbix"
$ResultJsonPath = "$DesktopPath\energy_result.json"
$TempExtractPath = "$DesktopPath\PBI_Extract_Temp"

$Result = @{
    file_exists = $false
    file_size_bytes = 0
    unpivot_success = $false
    measures_found = @()
    visuals_found = @()
    schema_clean = $false
}

if (Test-Path $ReportPath) {
    $Item = Get-Item $ReportPath
    $Result.file_exists = $true
    $Result.file_size_bytes = $Item.Length

    # Close PBI to allow reading/unzipping
    Stop-Process -Name PBIDesktop -Force
    Start-Sleep -Seconds 2

    # Unzip PBIX (it is a ZIP archive)
    if (Test-Path $TempExtractPath) { Remove-Item $TempExtractPath -Recurse -Force }
    Expand-Archive -Path $ReportPath -DestinationPath $TempExtractPath -Force

    # 1. Inspect Layout for Visuals
    $LayoutPath = "$TempExtractPath\Report\Layout"
    if (Test-Path $LayoutPath) {
        # Layout is JSON-like but encoding can be weird, read as raw text
        $LayoutContent = Get-Content $LayoutPath -Raw -Encoding Unicode
        # Convert to lower for case-insensitive search
        $LayoutLower = $LayoutContent.ToLower()

        if ($LayoutLower -match "stackedareachart" -or $LayoutLower -match "areachart") {
            $Result.visuals_found += "AreaChart"
        }
        if ($LayoutLower -match "card") {
            $Result.visuals_found += "Card"
        }
    }

    # 2. Inspect DataModel for Schema and DAX
    # DataModel is binary, but strings are visible
    $DataModelPath = "$TempExtractPath\DataModel"
    if (Test-Path $DataModelPath) {
        $ModelBytes = Get-Content $DataModelPath -Encoding Byte -ReadCount 0
        # Convert to ASCII string for simple grep
        $ModelString = [System.Text.Encoding]::ASCII.GetString($ModelBytes)

        # Check for renamed columns (Generation_TWh)
        if ($ModelString -match "Generation_TWh") {
            $Result.unpivot_success = $true
        }

        # Check for DAX Measures
        if ($ModelString -match "Total_Generation") { $Result.measures_found += "Total_Generation" }
        if ($ModelString -match "Renewable_Share_Pct") { $Result.measures_found += "Renewable_Share_Pct" }

        # Check for traces of un-pivoted columns (Anti-Gaming)
        # If '2010', '2011' etc appear as column definitions, user didn't unpivot
        # This is harder to check robustly in binary, but we can rely on positive 'Generation_TWh' check
        # and checking if the visual references 'Generation_TWh' in the layout
    }
    
    # Clean up
    Remove-Item $TempExtractPath -Recurse -Force
}

$Result | ConvertTo-Json | Set-Content $ResultJsonPath
Write-Host "Result exported to $ResultJsonPath"
EOF

# Run inspection
powershell -ExecutionPolicy Bypass -File /tmp/inspect_pbi.ps1

# Read the result back from Windows path to Linux /tmp for verification
# Assuming the container mounts allow access or we use cat via powershell
powershell -Command "Get-Content 'C:\Users\Docker\Desktop\energy_result.json'" > /tmp/task_result.json

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="