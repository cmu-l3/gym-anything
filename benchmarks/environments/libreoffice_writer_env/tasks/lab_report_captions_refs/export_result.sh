#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Output File Info
OUTPUT_PATH="/home/ga/Documents/soil_report_final.docx"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
fi

# 3. Get Task Start Time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 4. Check if created/modified during task
WAS_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
    WAS_MODIFIED="true"
fi

# 5. Check if App is Running
APP_RUNNING="false"
if pgrep -f "soffice.bin" > /dev/null; then
    APP_RUNNING="true"
    # Close it gracefully
    safe_xdotool ga :1 key ctrl+q
    sleep 1
    safe_xdotool ga :1 key alt+d # Don't save if prompt appears
fi

# 6. Create JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": $FILE_EXISTS,
    "output_size": $FILE_SIZE,
    "modified_during_task": $WAS_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete."