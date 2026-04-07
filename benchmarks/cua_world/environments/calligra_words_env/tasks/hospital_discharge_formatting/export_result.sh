#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Hospital Discharge Formatting Result ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

take_screenshot /tmp/calligra_hospital_discharge_post_task.png

OUTPUT_PATH="/home/ga/Documents/discharge_summary_raw.odt"
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" "$OUTPUT_PATH" || true
else
    echo "Warning: $OUTPUT_PATH is missing"
fi

# Do not force-save. The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/calligra_hospital_discharge_post_task.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="