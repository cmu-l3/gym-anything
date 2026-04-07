#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting NYC LL97 Compliance Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application is running and try to save
APP_RUNNING="false"
if is_onlyoffice_running; then
    APP_RUNNING="true"
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure it's dead
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/ll97_compliance_model.xlsx"

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo 0)
    
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    echo "Compliance model saved: $OUTPUT_PATH ($FILE_SIZE bytes)"
else
    echo "Compliance model not found at expected path: $OUTPUT_PATH"
fi

# Write result to JSON
cat > /tmp/task_result.json << JSONEOF
{
  "task_name": "nyc_ll97_emissions_compliance",
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_was_running": $APP_RUNNING,
  "output_exists": $FILE_EXISTS,
  "output_size_bytes": $FILE_SIZE,
  "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
  "screenshot_path": "/tmp/task_final.png"
}
JSONEOF

echo "=== Export Complete ==="