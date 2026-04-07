#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Voter Pamphlet Layout Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Focus and capture final state
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
    sleep 1
fi
take_screenshot /tmp/task_final.png

FILE_MODIFIED_DURING_TASK="false"
if [ -f "/home/ga/Documents/voter_pamphlet.odt" ]; then
    OUTPUT_MTIME=$(stat -c %Y "/home/ga/Documents/voter_pamphlet.odt" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" "/home/ga/Documents/voter_pamphlet.odt" || true
else
    echo "Warning: /home/ga/Documents/voter_pamphlet.odt is missing"
fi

# Quit gracefully
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2
kill_calligra_processes

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="