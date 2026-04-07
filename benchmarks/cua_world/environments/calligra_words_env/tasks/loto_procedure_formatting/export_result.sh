#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting LOTO Procedure Formatting Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Bring window to front before screenshot
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
    sleep 0.5
fi

# Take final screenshot showing what the agent accomplished
take_screenshot /tmp/loto_procedure_formatting_post_task.png

# Check file modification timestamp to see if work was saved
FILE_MODIFIED="false"
if [ -f "/home/ga/Documents/LOTO_Cincinnati_Press.odt" ]; then
    FILE_MTIME=$(stat -c %Y "/home/ga/Documents/LOTO_Cincinnati_Press.odt" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" "/home/ga/Documents/LOTO_Cincinnati_Press.odt" || true
else
    echo "Warning: /home/ga/Documents/LOTO_Cincinnati_Press.odt is missing"
fi

# Safely close Calligra Words
# Do not force-save (Ctrl+S). The agent must persist its own changes.
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

# Create a metadata export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED
}
EOF

mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="