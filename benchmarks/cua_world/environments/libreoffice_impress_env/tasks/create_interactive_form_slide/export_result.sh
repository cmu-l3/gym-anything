#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Save the file (Ctrl+S)
echo "Saving presentation..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key ctrl+s
    sleep 2
fi

# 2. Capture Final Screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Gather File Statistics
FILE_PATH="/home/ga/Documents/Presentations/warehouse_safety.odp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$FILE_PATH" ]; then
    MTIME=$(stat -c %Y "$FILE_PATH")
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. JSON Export
cat << EOF > /tmp/task_result.json
{
    "file_exists": $([ -f "$FILE_PATH" ] && echo "true" || echo "false"),
    "file_modified": $FILE_MODIFIED,
    "file_path": "$FILE_PATH",
    "file_size": $FILE_SIZE,
    "task_start_time": $TASK_START,
    "timestamp": $(date +%s)
}
EOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"