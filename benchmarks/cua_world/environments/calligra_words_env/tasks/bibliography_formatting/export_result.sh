#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Bibliography Formatting Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOC_PATH="/home/ga/Documents/vaccine_hesitancy_brief.odt"

# Check file modification to ensure agent actually worked
FILE_MODIFIED="false"
if [ -f "$DOC_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Bring Calligra to front to capture the final UI state
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
    sleep 1
fi

take_screenshot /tmp/task_final.png ga

# Create a temporary JSON result record
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified_during_task": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Let the agent's work persist natively (don't force kill saving operations)
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="