#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting ED Throughput & LOS Analysis Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
su - ga -c "DISPLAY=:1 import -window root /tmp/task_final.png" || true

# Check if application is running and gracefully save
APP_RUNNING="false"
if is_onlyoffice_running; then
    APP_RUNNING="true"
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

REPORT_PATH="/home/ga/Documents/Spreadsheets/ed_operations_dashboard.xlsx"
OUTPUT_PATH="$REPORT_PATH"

OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    echo "Dashboard saved: $REPORT_PATH"
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo 0)
    OUTPUT_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo 0)
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    echo "Dashboard not found at exact path. Checking alternatives..."
    ALT_FILE=$(ls -t /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null | head -1 || echo "")
    if [ -n "$ALT_FILE" ]; then
        echo "Found alternative file: $ALT_FILE"
        cp "$ALT_FILE" "$REPORT_PATH"
        OUTPUT_EXISTS="true"
        OUTPUT_SIZE=$(stat -c%s "$ALT_FILE" 2>/dev/null || echo 0)
        OUTPUT_MTIME=$(stat -c%Y "$ALT_FILE" 2>/dev/null || echo 0)
        if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Export result JSON
TEMP_JSON=$(mktemp /tmp/ed_result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
  "task_name": "ed_throughput_los_analysis",
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "output_exists": $OUTPUT_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "output_size_bytes": $OUTPUT_SIZE,
  "app_was_running": $APP_RUNNING,
  "screenshot_path": "/tmp/task_final.png"
}
JSONEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="