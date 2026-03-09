#!/bin/bash
echo "=== Setting up Construct Stone Planter Task ==="

# Define paths (Git Bash / Cygwin path to Windows path)
TASK_START_FILE="/tmp/task_start_time.txt"
START_TIMESTAMP=$(date +%s)
echo "$START_TIMESTAMP" > "$TASK_START_FILE"

# Clean up previous results
rm -f /mnt/c/Users/Docker/Documents/stone_planter.dpp 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure DreamPlan is running
echo "Checking DreamPlan process..."
if ! tasklist.exe | grep -i "dreamplan.exe" > /dev/null; then
    echo "Starting DreamPlan..."
    # Launch via PowerShell to handle path correctly
    powershell.exe -Command "Start-Process 'C:\Program Files (x86)\NCH Software\DreamPlan\dreamplan.exe'"
    
    # Wait for window
    for i in {1..30}; do
        if tasklist.exe | grep -i "dreamplan.exe" > /dev/null; then
            echo "Process started."
            break
        fi
        sleep 1
    done
    sleep 5 # Allow GUI to load
fi

# Maximize Window using PowerShell
echo "Maximizing DreamPlan window..."
powershell.exe -Command "
\$wshell = New-Object -ComObject WScript.Shell;
\$wshell.AppActivate('DreamPlan');
Sleep 1;
\$wshell.SendKeys('% x'); # Alt+Space, x to maximize
" 2>/dev/null || true

# Capture initial screenshot using a Windows screenshot tool or gym-anything utility if available
# Fallback to PowerShell snippet for screenshot if scrot not available on Windows env
echo "Capturing initial screenshot..."
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen;
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height;
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap);
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size);
\$bitmap.Save('C:\Users\Docker\AppData\Local\Temp\task_initial.png');
" 2>/dev/null || true

# Move screenshot to /tmp for consistency with linux-based expectations (mapped via mount)
if [ -f "/mnt/c/Users/Docker/AppData/Local/Temp/task_initial.png" ]; then
    cp "/mnt/c/Users/Docker/AppData/Local/Temp/task_initial.png" /tmp/task_initial.png
fi

echo "=== Setup Complete ==="