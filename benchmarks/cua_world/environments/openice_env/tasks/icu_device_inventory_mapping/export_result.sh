#!/bin/bash
echo "=== Exporting ICU Device Inventory Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Get file metadata (existence, timestamp)
CSV_FILE="/home/ga/Desktop/icu_inventory.csv"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"

if [ -f "$CSV_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$CSV_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
fi

# 3. Capture Window State (to verify 3 devices are open)
WINDOW_COUNT=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "device|adapter|monitor|pump|pulse" | wc -l)

# 4. Extract ONLY the log lines generated during this task
# This is crucial for matching the UUIDs found in the CSV to the actual session
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_OFFSET=$(cat /tmp/initial_log_offset 2>/dev/null || echo "0")
TASK_LOG_PATH="/tmp/task_session.log"

if [ -f "$LOG_FILE" ]; then
    # Tail from the byte offset + 1
    tail -c +$((INITIAL_OFFSET + 1)) "$LOG_FILE" > "$TASK_LOG_PATH"
else
    touch "$TASK_LOG_PATH"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $(cat /tmp/task_start_timestamp 2>/dev/null || echo "0"),
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "active_device_windows": $WINDOW_COUNT,
    "csv_path": "$CSV_FILE",
    "session_log_path": "$TASK_LOG_PATH",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Important: Make sure the csv and log are readable by the verifier (via copy_from_env)
chmod 644 "$CSV_FILE" 2>/dev/null || true
chmod 644 "$TASK_LOG_PATH" 2>/dev/null || true

echo "=== Export Complete ==="