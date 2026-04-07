#!/bin/bash
set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "=== Exporting Forensic Audit Report Result ==="

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

FILE_PATH="/home/ga/Documents/project_chariot_investigation.odt"
if [ -f "$FILE_PATH" ]; then
    MTIME=$(stat -c %Y "$FILE_PATH")
    SIZE=$(stat -c %s "$FILE_PATH")
else
    MTIME=0
    SIZE=0
fi

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Save file metadata to JSON
cat > /tmp/task_result.json << EOF
{
    "mtime": $MTIME,
    "size": $SIZE,
    "start_time": $START_TIME
}
EOF

# Provide time for graceful quit, but don't force save
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="