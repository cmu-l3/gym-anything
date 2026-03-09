#!/bin/bash
# export_result.sh for chem_inventory_formatting

source /workspace/scripts/task_utils.sh

echo "=== Exporting Chemical Inventory Formatting Results ==="

# 1. Take final screenshot (CRITICAL for visual verification)
take_screenshot /tmp/task_final.png

# 2. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# 3. Check for Output File
OUTPUT_FILE="/home/ga/Documents/chem_inventory_formatted.docx"
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check if file was modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    echo "Output file found ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at $OUTPUT_FILE"
fi

# 4. Check if LibreOffice is still running
APP_RUNNING="false"
if pgrep -f "soffice" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create basic JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "output_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions for the JSON file
chmod 666 /tmp/task_result.json

# Close Writer gracefully to ensure no lock files remain (optional but good hygiene)
# We don't force kill immediately to allow agent to see the result if they are watching
# But for automated cleanup:
if [ "$APP_RUNNING" = "true" ]; then
    echo "Closing LibreOffice..."
    safe_xdotool ga :1 key ctrl+q
    sleep 2
    # Handle "Save Changes" dialog if it appears (press Don't Save / Discard)
    safe_xdotool ga :1 key alt+d 2>/dev/null || true
fi

echo "=== Export Complete ==="