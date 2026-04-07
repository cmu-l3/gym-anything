#!/bin/bash
echo "=== Exporting calculate_polygon_area task result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/c/Users/Docker/Documents/parcel_area_report.txt"

# Take final screenshot
powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    \$bitmap = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
    \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap)
    \$graphics.CopyFromScreen([System.Drawing.Point]::Empty, [System.Drawing.Point]::Empty, \$bitmap.Size)
    \$bitmap.Save('C:\tmp\task_final.png')
    \$graphics.Dispose()
    \$bitmap.Dispose()
" 2>/dev/null || true

# Evaluate expected output file
if [ -f "$REPORT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check if created/modified after task started (anti-gaming)
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Read file content safely, escaping line breaks and quotes
    FILE_CONTENT=$(cat "$REPORT_PATH" | tr -d '\r' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    FILE_CONTENT=""
fi

# Check if application is running
APP_RUNNING=$(powershell.exe -Command "Get-Process -Name 'TopoCal*' -ErrorAction SilentlyContinue" 2>/dev/null | grep -i topocal > /dev/null && echo "true" || echo "false")

# Create JSON payload using a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": "$FILE_CONTENT",
    "app_was_running": $APP_RUNNING
}
EOF

# Move to standard location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="