#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Clinical Protocol Formatting Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Focus window before screenshot
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi
sleep 1

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Check for output file (FINAL or draft if they overwrote it)
OUTPUT_PATH="/home/ga/Documents/adult_sepsis_protocol_FINAL.odt"
DRAFT_PATH="/home/ga/Documents/adult_sepsis_protocol_draft.odt"

EVAL_PATH=""
if [ -f "$OUTPUT_PATH" ]; then
    EVAL_PATH="$OUTPUT_PATH"
elif [ -f "$DRAFT_PATH" ]; then
    EVAL_PATH="$DRAFT_PATH"
fi

if [ -n "$EVAL_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$EVAL_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    else
        FILE_MODIFIED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$EVAL_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    FILE_MODIFIED_DURING_TASK="false"
    OUTPUT_SIZE="0"
    EVAL_PATH=""
fi

# Do not force-save via xdotool to prevent gaming. Agent must explicitly save.
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
    "eval_path": "$EVAL_PATH",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="