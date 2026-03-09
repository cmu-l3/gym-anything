#!/bin/bash
echo "=== Exporting Map WNV Positives Result ==="

# Define paths
OUTPUT_FILE="/c/Users/Docker/Documents/EpiData/wnv_positive_map.png"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot (PowerShell method for Windows)
echo "Capturing final state..."
powershell -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.Location, [System.Drawing.Point]::Empty, \$screen.Bounds.Size)
\$bitmap.Save('C:\\Users\\Docker\\AppData\\Local\\Temp\\task_final.png', [System.Drawing.Imaging.ImageFormat]::Png)
\$graphics.Dispose()
\$bitmap.Dispose()
" >/dev/null 2>&1 || true

cp "/c/Users/Docker/AppData/Local/Temp/task_final.png" /tmp/task_final.png 2>/dev/null || true

# Verify Output File
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check creation time
    TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Epi Map is running
APP_RUNNING="false"
if powershell -Command "Get-Process EpiMap -ErrorAction SilentlyContinue" >/dev/null 2>&1; then
    APP_RUNNING="true"
fi

# Create Result JSON
cat > "$RESULT_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="