#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting eDiscovery Privilege Log Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing application
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Save and safely close ONLYOFFICE if running
if is_onlyoffice_running; then
    echo "Saving and closing ONLYOFFICE..."
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/Privilege_Log.xlsx"
FILE_CREATED_DURING_TASK="false"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if the file was created/modified after the task started
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Privilege Log saved: $OUTPUT_PATH (Size: $OUTPUT_SIZE bytes)"
else
    echo "Privilege Log not found at expected path: $OUTPUT_PATH"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/ediscovery_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/ediscovery_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ediscovery_task_result.json
chmod 666 /tmp/ediscovery_task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="