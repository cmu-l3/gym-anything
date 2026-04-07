#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting DR Runbook Formatting Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_PATH="/home/ga/Documents/postgres_failover_runbook.odt"

# 1. Take final screenshot
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
fi
take_screenshot /tmp/calligra_dr_runbook_post_task.png

# 2. Check file modification
FILE_MODIFIED="false"
if [ -f "$FILE_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
else
    FILE_MTIME="0"
    FILE_SIZE="0"
fi

# 3. Create JSON Result 
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_path": "/tmp/calligra_dr_runbook_post_task.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# 4. Clean exit (do not force save, agent must save their work)
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2
kill_calligra_processes

echo "=== Export Complete ==="