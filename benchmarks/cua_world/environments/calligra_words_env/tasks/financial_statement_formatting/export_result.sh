#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Focus window and take final screenshot
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi
sleep 1
take_screenshot /tmp/task_final.png

# Check document status
OUTPUT_PATH="/home/ga/Documents/novatech_financials.odt"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    else
        FILE_MODIFIED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
else
    OUTPUT_EXISTS="false"
    FILE_MODIFIED_DURING_TASK="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Let the agent's save persist, but gracefully kill the UI if possible
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2
kill_calligra_processes

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="