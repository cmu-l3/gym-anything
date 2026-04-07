#!/bin/bash
echo "=== Setting up Create Multilayer Map task ==="

# Define paths (using Windows style for PowerShell compatibility)
DOCS_DIR="C:\Users\Docker\Documents"
TARGET_FILE="$DOCS_DIR\Geospatial_Analysis.dva"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous task artifacts
echo "Cleaning up old files..."
rm -f "/c/Users/Docker/Documents/Geospatial_Analysis.dva" 2>/dev/null || true
# Also try PowerShell remove for robustness
powershell.exe -Command "Remove-Item -Path '$TARGET_FILE' -ErrorAction SilentlyContinue"

# Record initial file state
if [ -f "/c/Users/Docker/Documents/Geospatial_Analysis.dva" ]; then
    echo "WARNING: Failed to delete previous file"
    echo "exists" > /tmp/initial_file_state.txt
else
    echo "absent" > /tmp/initial_file_state.txt
fi

# Ensure Oracle Analytics Desktop is running
# Note: Process name might be 'Oracle Analytics Desktop' or similar binary name
echo "Checking application status..."
PROCESS_RUNNING=$(powershell.exe -Command "Get-Process -Name 'Oracle Analytics Desktop' -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count")

if [ "$PROCESS_RUNNING" -eq "0" ]; then
    echo "Starting Oracle Analytics Desktop..."
    # Assuming standard install path or shortcut availability
    powershell.exe -Command "Start-Process 'C:\Program Files\Oracle Analytics Desktop\Oracle Analytics Desktop.exe' -WindowStyle Maximized"
    
    # Wait for startup (OAD can be slow)
    echo "Waiting for application to load..."
    for i in {1..30}; do
        PROCESS_RUNNING=$(powershell.exe -Command "Get-Process -Name 'Oracle Analytics Desktop' -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count")
        if [ "$PROCESS_RUNNING" -gt "0" ]; then
            echo "Application process detected."
            sleep 10 # Allow UI to render
            break
        fi
        sleep 2
    done
else
    echo "Application is already running."
    # Bring to front
    powershell.exe -Command "
    \$wshell = New-Object -ComObject wscript.shell;
    \$wshell.AppActivate('Oracle Analytics Desktop')
    "
fi

# Take initial screenshot
echo "Capturing initial state..."
# Using PowerShell to take screenshot if scrot not available, or use environment tool
# Assuming standard Linux tools exist in the shell environment (like Git Bash) or using a python one-liner
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
\$bitmap.Save('C:\Users\Docker\AppData\Local\Temp\task_initial.png')
"
# Move to /tmp for consistency with export script
cp "/c/Users/Docker/AppData/Local/Temp/task_initial.png" /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="