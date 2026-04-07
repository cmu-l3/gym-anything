#!/bin/bash
set -euo pipefail

echo "=== Exporting Hurricane Evacuation Briefing Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before closing
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Give agent a chance to have saved, but attempt a safe save operation just in case
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    # We do NOT force save the file as a specific name - the agent was supposed to do that.
    # We just cleanly close the application.
    sleep 1
    kill_onlyoffice ga
    sleep 2
fi

OUTPUT_PATH="/home/ga/Documents/Presentations/ian_briefing.pptx"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found presentation: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "Presentation not found at expected path."
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="