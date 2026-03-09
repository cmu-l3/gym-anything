#!/bin/bash
set -e

echo "=== Exporting Configure Fixed Price Axis Result ==="

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"
FINAL_SCREENSHOT="/tmp/task_final.png"

# 1. Take Final Screenshot
if command -v scrot &> /dev/null; then
    DISPLAY=:1 scrot "$FINAL_SCREENSHOT"
else
    # PowerShell fallback for screenshot
    powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('{PRTSC}'); Start-Sleep -m 500; \$img = [System.Windows.Forms.Clipboard]::GetImage(); if (\$img) { \$img.Save('$FINAL_SCREENSHOT') }"
fi

# 2. Create PowerShell script to analyze NinjaTrader Workspaces
#    This script parses the XML files to find the configuration
PS_EXPORT_SCRIPT="/tmp/export_result_internal.ps1"

cat << EOF > "$PS_EXPORT_SCRIPT"
\$ErrorActionPreference = "Stop"
\$TaskStartTime = $TASK_START_TIME

# Paths
\$WorkspacesDir = [System.IO.Path]::Combine([System.Environment]::GetFolderPath('MyDocuments'), "NinjaTrader 8", "workspaces")
\$ResultPath = "$RESULT_JSON"

# Initialize Result Object
\$Result = @{
    workspace_found = \$false
    workspace_modified = \$false
    chart_found = \$false
    spy_instrument_found = \$false
    is_auto_scale = \$null
    fixed_min = \$null
    fixed_max = \$null
    timestamp = (Get-Date).ToString("o")
}

# Find most recently modified workspace XML file (excluding _Workspaces.xml)
if (Test-Path \$WorkspacesDir) {
    \$LatestFile = Get-ChildItem -Path \$WorkspacesDir -Filter "*.xml" | 
                  Where-Object { \$_.Name -ne "_Workspaces.xml" } | 
                  Sort-Object LastWriteTime -Descending | 
                  Select-Object -First 1

    if (\$LatestFile) {
        \$Result.workspace_found = \$true
        
        # Check modification time against task start
        \$ModTimeUnix = (New-TimeSpan -Start (Get-Date "01/01/1970") -End \$LatestFile.LastWriteTime.ToUniversalTime()).TotalSeconds
        if (\$ModTimeUnix -gt \$TaskStartTime) {
            \$Result.workspace_modified = \$true
        }

        # Parse XML
        try {
            [xml]\$xml = Get-Content \$LatestFile.FullName
            
            # Look for Chart Controls
            \$Charts = \$xml.SelectNodes("//ChartControl")
            
            foreach (\$Chart in \$Charts) {
                # Check Instrument (BarsSeries -> Instrument -> MasterInstrument -> Name)
                # Structure varies slightly by version, searching loosely
                \$InstrumentName = \$Chart.SelectSingleNode(".//Instrument//MasterInstrument").Name
                
                if (\$InstrumentName -match "SPY") {
                    \$Result.chart_found = \$true
                    \$Result.spy_instrument_found = \$true
                    
                    # Check Axis Properties
                    # Usually found in <ChartScales> collection
                    \$Scales = \$Chart.SelectNodes(".//ChartScale")
                    
                    foreach (\$Scale in \$Scales) {
                        # We are looking for the primary price scale (Right or Left, usually Right)
                        # Check properties: IsAutoSize, MaxValue, MinValue
                        
                        # Note: XML property names match C# class properties
                        \$IsAuto = \$Scale.IsAutoSize
                        \$Max = \$Scale.MaxValue
                        \$Min = \$Scale.MinValue
                        
                        # Store values (convert to simpler types)
                        \$Result.is_auto_scale = (\$IsAuto -eq "true")
                        \$Result.fixed_max = -1.0
                        \$Result.fixed_min = -1.0
                        
                        if (\$Max) { \$Result.fixed_max = [double]\$Max }
                        if (\$Min) { \$Result.fixed_min = [double]\$Min }
                        
                        # If we found a fixed scale configuration, break loop
                        if (\$IsAuto -eq "false") {
                            break
                        }
                    }
                    break # Found SPY chart
                }
            }
        } catch {
            Write-Host "Error parsing XML: \$_"
        }
    }
}

# Convert to JSON and save
\$Result | ConvertTo-Json -Depth 5 | Set-Content -Path \$ResultPath -Encoding UTF8
Write-Host "Result exported to \$ResultPath"
EOF

# 3. Run the export logic
echo "Running PowerShell export logic..."
powershell.exe -ExecutionPolicy Bypass -File "$PS_EXPORT_SCRIPT"

# 4. Ensure permissions for host to read
chmod 666 "$RESULT_JSON" 2>/dev/null || true
if [ -f "$FINAL_SCREENSHOT" ]; then
    chmod 666 "$FINAL_SCREENSHOT" 2>/dev/null || true
fi

echo "=== Export Complete ==="
cat "$RESULT_JSON"