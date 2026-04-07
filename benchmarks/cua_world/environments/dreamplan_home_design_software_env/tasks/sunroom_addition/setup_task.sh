#!/bin/bash
echo "=== Setting up sunroom_addition task ==="

# ---------- 1. Clean stale output files from previous runs ----------
echo "Cleaning previous output files..."
rm -f "/mnt/c/Users/Docker/Desktop/sunroom_floorplan.jpg" 2>/dev/null || true
rm -f "/mnt/c/Users/Docker/Desktop/sunroom_exterior.jpg" 2>/dev/null || true
rm -f "/mnt/c/Users/Docker/Desktop/sunroom_interior.jpg" 2>/dev/null || true
rm -f "/mnt/c/Users/Docker/Documents/sunroom_design.dpn" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# ---------- 2. Record task start timestamp (AFTER cleaning) ----------
START_TIMESTAMP=$(date +%s)
echo "$START_TIMESTAMP" > /tmp/task_start_time.txt
echo "Task start timestamp: $START_TIMESTAMP"

# ---------- 3. Ensure DreamPlan is running with Contemporary House ----------
echo "Checking DreamPlan process..."
if ! tasklist.exe 2>/dev/null | grep -qi "dreamplan.exe"; then
    echo "DreamPlan not running. Starting DreamPlan..."
    powershell.exe -Command "Start-Process 'C:\Program Files (x86)\NCH Software\DreamPlan\dreamplan.exe'" 2>/dev/null || \
    powershell.exe -Command "Start-Process 'C:\Program Files\NCH Software\DreamPlan\dreamplan.exe'" 2>/dev/null || true

    # Wait for process to start
    for i in {1..30}; do
        if tasklist.exe 2>/dev/null | grep -qi "dreamplan.exe"; then
            echo "DreamPlan process detected."
            break
        fi
        sleep 1
    done
    sleep 10  # Allow GUI to fully load
else
    echo "DreamPlan is already running."
fi

# ---------- 4. Maximize and focus DreamPlan window ----------
echo "Maximizing DreamPlan window..."
powershell.exe -Command "
\$wshell = New-Object -ComObject WScript.Shell;
\$wshell.AppActivate('DreamPlan');
Start-Sleep -Seconds 1;
\$wshell.SendKeys('% x');
" 2>/dev/null || true

# ---------- 5. Kill Microsoft Edge to prevent interference ----------
echo "Killing Edge processes..."
powershell.exe -Command "Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue" 2>/dev/null || true

# ---------- 6. Capture initial screenshot for evidence ----------
echo "Capturing initial screenshot..."
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen;
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height;
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap);
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size);
\$bitmap.Save('C:\Users\Docker\AppData\Local\Temp\task_initial.png');
\$graphics.Dispose();
\$bitmap.Dispose();
" 2>/dev/null || true

if [ -f "/mnt/c/Users/Docker/AppData/Local/Temp/task_initial.png" ]; then
    cp "/mnt/c/Users/Docker/AppData/Local/Temp/task_initial.png" /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== sunroom_addition setup complete ==="
