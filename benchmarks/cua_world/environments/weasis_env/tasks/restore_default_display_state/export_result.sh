#!/bin/bash
echo "=== Exporting restore_default_display_state result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"

FILE_1="$EXPORT_DIR/state_1_initial.jpg"
FILE_2="$EXPORT_DIR/state_2_altered.jpg"
FILE_3="$EXPORT_DIR/state_3_restored.jpg"

check_file() {
    local filepath=$1
    if [ -f "$filepath" ]; then
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local valid_time="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            valid_time="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"valid_time\": $valid_time, \"path\": \"$filepath\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"valid_time\": false, \"path\": \"$filepath\"}"
    fi
}

F1_JSON=$(check_file "$FILE_1")
F2_JSON=$(check_file "$FILE_2")
F3_JSON=$(check_file "$FILE_3")

# Check if application was running
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "file_1": $F1_JSON,
    "file_2": $F2_JSON,
    "file_3": $F3_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="