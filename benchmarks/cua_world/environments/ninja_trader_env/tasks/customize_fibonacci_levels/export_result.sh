#!/bin/bash
echo "=== Exporting Fibonacci Task Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use PowerShell to inspect the workspace XML files
# We output the analysis to a JSON file
powershell.exe -Command "& {
    $taskStart = $env:TASK_START
    $workspaceDir = 'C:\Users\Docker\Documents\NinjaTrader 8\workspaces'
    $resultPath = 'C:\tmp\task_result.json'
    mkdir 'C:\tmp' -Force | Out-Null
    
    # Initialize result object
    $result = @{
        workspace_modified = \$false
        fib_tool_found = \$false
        level_786_found = \$false
        level_236_found = \$false
        level_618_color = 'None'
        chart_instrument = 'None'
        timestamp = (Get-Date).ToString('o')
    }

    # Find modified workspace files
    $recentFiles = Get-ChildItem -Path \$workspaceDir -Recurse -Filter '*.xml' | 
                   Where-Object { \$_.LastWriteTime.ToFileTime() -gt 0 } | # rudimentary check
                   Sort-Object LastWriteTime -Descending

    # Iterate through recent files to find the config
    foreach (\$file in \$recentFiles) {
        # Check if modified after task start (converting unix timestamp roughly)
        # Note: Precision might be tricky across OS boundaries, so we check content mainly
        
        try {
            [xml]\$xml = Get-Content \$file.FullName
            
            # Check for Fib tool
            \$fibs = \$xml.SelectNodes('//FibonacciRetracements')
            
            if (\$fibs.Count -gt 0) {
                \$result.fib_tool_found = \$true
                \$result.workspace_modified = \$true # Assumption: if we found it in a recent file
                
                # Check specific instance
                foreach (\$fib in \$fibs) {
                    # Check Levels
                    # XML structure usually: <Levels><ChartScaleLevel><Value>0.786</Value>...
                    \$levels = \$fib.SelectNodes('.//Levels//ChartScaleLevel')
                    
                    foreach (\$level in \$levels) {
                        \$valNode = \$level.SelectSingleNode('Value')
                        if (\$valNode) {
                            \$val = [double]\$valNode.InnerText
                            
                            if ([Math]::Abs(\$val - 0.786) -lt 0.001 -or [Math]::Abs(\$val - 78.6) -lt 0.001) {
                                \$result.level_786_found = \$true
                            }
                            if ([Math]::Abs(\$val - 0.236) -lt 0.001 -or [Math]::Abs(\$val - 23.6) -lt 0.001) {
                                \$result.level_236_found = \$true
                            }
                            if ([Math]::Abs(\$val - 0.618) -lt 0.001 -or [Math]::Abs(\$val - 61.8) -lt 0.001) {
                                # Check color
                                # Structure: <Stroke><SolidColorBrush><Color>...
                                # Or <Pen><Color>... - NT8 structure varies, checking usually <Stroke>
                                \$stroke = \$level.SelectSingleNode('.//Stroke')
                                if (\$stroke) {
                                    \$color = \$stroke.InnerXml
                                    # Very naive color extraction, looking for 'Red' or specific ARGB
                                    # ARGB for Red is often #FFFF0000
                                    if (\$color -match 'Red' -or \$color -match '#FFFF0000') {
                                        \$result.level_618_color = 'Red'
                                    } else {
                                        \$result.level_618_color = 'Other'
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            # Check Instrument (looking for ChartBars or similar)
            \$chartBars = \$xml.SelectSingleNode('//ChartBars//Instrument//MasterInstrument//Name')
            if (\$chartBars) {
                \$result.chart_instrument = \$chartBars.InnerText
            }
            
            if (\$result.fib_tool_found) { break }
        } catch {
            Write-Host 'Error parsing file: ' \$_.FullName
        }
    }

    \$result | ConvertTo-Json | Set-Content \$resultPath
}"

# Copy the result back to Linux /tmp for verification
cp /mnt/c/tmp/task_result.json /tmp/task_result.json 2>/dev/null || cp "C:\tmp\task_result.json" /tmp/task_result.json 2>/dev/null

# Take final screenshot
powershell.exe -Command "& {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bitmap.Size)
    $bitmap.Save('C:\tmp\task_final.png')
}"
cp /mnt/c/tmp/task_final.png /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="