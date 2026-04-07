#!/bin/bash
echo "=== Exporting Create Multilayer Map result ==="

# Paths
DOCS_DIR="/c/Users/Docker/Documents"
TARGET_FILE="$DOCS_DIR/Geospatial_Analysis.dva"
WIN_TARGET_FILE="C:\Users\Docker\Documents\Geospatial_Analysis.dva"

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$screen = [System.Windows.Forms.Screen]::PrimaryScreen
\$bitmap = New-Object System.Drawing.Bitmap \$screen.Bounds.Width, \$screen.Bounds.Height
\$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
\$graphics.CopyFromScreen(\$screen.Bounds.X, \$screen.Bounds.Y, 0, 0, \$bitmap.Size)
\$bitmap.Save('C:\Users\Docker\AppData\Local\Temp\task_final.png')
"
cp "/c/Users/Docker/AppData/Local/Temp/task_final.png" /tmp/task_final.png 2>/dev/null || true

# Verify Output File
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    OUTPUT_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy DVA to tmp for easy retrieval by verifier
    cp "$TARGET_FILE" /tmp/Geospatial_Analysis.dva
fi

# Check if App is running
APP_RUNNING="false"
PROCESS_CHECK=$(powershell.exe -Command "Get-Process -Name 'Oracle Analytics Desktop' -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count")
if [ "$PROCESS_CHECK" -gt "0" ]; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "dva_file_path": "/tmp/Geospatial_Analysis.dva"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json