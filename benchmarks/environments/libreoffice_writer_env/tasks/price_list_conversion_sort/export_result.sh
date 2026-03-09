#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Price List Conversion Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/formatted_price_list.docx"

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus Writer window (if still open) to ensure screenshot captures context
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Check file status
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_path": "$OUTPUT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Attempt to close LibreOffice gracefully
# This prevents "Recover File" dialogs in subsequent tasks
echo "Closing LibreOffice..."
if [ -n "$wid" ]; then
    # Ctrl+Q to quit
    safe_xdotool ga :1 key ctrl+q
    sleep 1
    # If "Save changes?" dialog appears, press "Don't Save" (Alt+D or Right+Enter)
    # We assume the agent already saved if they followed instructions.
    safe_xdotool ga :1 key Alt+d 2>/dev/null || true
fi

echo "=== Export complete ==="