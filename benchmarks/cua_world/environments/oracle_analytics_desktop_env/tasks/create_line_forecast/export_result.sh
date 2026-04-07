#!/bin/bash
echo "=== Exporting create_line_forecast result ==="

# Define paths
RESULT_JSON="/tmp/task_result.json"
WINDOWS_RESULT="C:\tmp\task_result.json"

# Execute verification logic in PowerShell and save to JSON
powershell.exe -Command "
    \$score = 0
    \$details = @{}
    \$taskStart = Get-Content 'C:\tmp\task_start_time.txt' -ErrorAction SilentlyContinue
    if (\$taskStart) { \$taskStart = [double]\$taskStart } else { \$taskStart = 0 }
    
    # 1. Check for Saved Workbook
    \$workbookFound = \$false
    \$workbookPath = ''
    \$searchPaths = @(
        'C:\Users\Docker\Desktop',
        'C:\Users\Docker\Documents',
        'C:\Users\Docker\AppData\Local\Oracle\DVDesktop'
    )
    
    # Recursive search for the workbook
    foreach (\$path in \$searchPaths) {
        if (Test-Path \$path) {
            \$files = Get-ChildItem -Path \$path -Recurse -Filter '*Supply_Chain_Forecast*.dva' -ErrorAction SilentlyContinue
            foreach (\$f in \$files) {
                # Convert Windows ticks to Unix timestamp for comparison
                \$modTime = (Get-Date \$f.LastWriteTime -UFormat '%s')
                if (\$modTime -gt \$taskStart) {
                    \$workbookFound = \$true
                    \$workbookPath = \$f.FullName
                    break
                }
            }
        }
        if (\$workbookFound) { break }
    }
    
    \$details['workbook_exists'] = \$workbookFound
    \$details['workbook_path'] = \$workbookPath
    
    # 2. Check OAD Process Status
    \$proc = Get-Process -Name 'DVDesktop' -ErrorAction SilentlyContinue
    \$details['app_running'] = [bool]\$proc
    
    # 3. Take Final Screenshot
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    \$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    \$bitmap = New-Object System.Drawing.Bitmap(\$screen.Width, \$screen.Height)
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
    \$graphics.CopyFromScreen(\$screen.Location, [System.Drawing.Point]::Empty, \$screen.Size)
    \$bitmap.Save('C:\tmp\task_final.png')
    \$graphics.Dispose()
    \$bitmap.Dispose()
    
    \$details['screenshot_path'] = 'C:\tmp\task_final.png'
    
    # Output JSON
    \$output = @{
        workbook_exists = \$workbookFound
        workbook_path = \$workbookPath
        app_running = [bool]\$proc
        timestamp = (Get-Date -UFormat '%s')
    }
    \$output | ConvertTo-Json | Out-File -FilePath '$WINDOWS_RESULT' -Encoding ascii
"

# Ensure the JSON file exists for the verifier to pick up
if [ ! -f "$WINDOWS_RESULT" ]; then
    # Fallback if PowerShell failed
    echo '{"workbook_exists": false, "error": "Export script failed"}' > "$RESULT_JSON"
else
    # Copy from Windows path to Linux/Container path if they differ (often mapped, but good to ensure)
    cp "$WINDOWS_RESULT" "$RESULT_JSON" 2>/dev/null || true
fi

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="