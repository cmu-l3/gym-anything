#!/bin/bash
echo "=== Exporting Stone Planter Task Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# Expected output file
WIN_PATH="C:\\Users\\Docker\\Documents\\stone_planter.dpp"
LINUX_PATH="/mnt/c/Users/Docker/Documents/stone_planter.dpp"

# Check if output exists
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
CONTENT_KEYWORDS_FOUND="false"

if [ -f "$LINUX_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$LINUX_PATH" 2>/dev/null || echo "0")
    
    # Check creation/mod time (Windows filesystem mounted in WSL/Linux can be tricky, using stat)
    FILE_MTIME=$(stat -c %Y "$LINUX_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Basic content check (DPP files are often text/XML/Ini)
    # Search for keywords indicating Block and Plant
    if grep -qi "Block" "$LINUX_PATH" || grep -qi "CustomMesh" "$LINUX_PATH"; then
        if grep -qi "Plant" "$LINUX_PATH" || grep -qi "Tree" "$LINUX_PATH"; then
             CONTENT_KEYWORDS_FOUND="true"
        fi
    fi
fi

# Check if App is still running
APP_RUNNING="false"
if tasklist.exe | grep -i "dreamplan.exe" > /dev/null; then
    APP_RUNNING="true"
fi

# Capture final screenshot
echo "Capturing final screenshot..."
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen;
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height;
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap);
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size);
\$bitmap.Save('C:\Users\Docker\AppData\Local\Temp\task_final.png');
" 2>/dev/null || true

if [ -f "/mnt/c/Users/Docker/AppData/Local/Temp/task_final.png" ]; then
    cp "/mnt/c/Users/Docker/AppData/Local/Temp/task_final.png" /tmp/task_final.png
fi

# Create result JSON
TEMP_JSON="/tmp/result_gen.json"
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "content_keywords_found": $CONTENT_KEYWORDS_FOUND,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="