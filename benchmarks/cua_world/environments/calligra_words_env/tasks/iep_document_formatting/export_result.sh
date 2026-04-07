#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting IEP Document Formatting Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_PATH="/home/ga/Documents/draft_iep_jordan.odt"

# Anti-gaming file modification check
FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Ensure window is focused for screenshot
wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
fi

# Final screenshot
take_screenshot /tmp/calligra_iep_formatting_post_task.png

# Generate JSON result block
TEMP_JSON=$(mktemp /tmp/iep_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_mtime": $FILE_MTIME,
    "file_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/calligra_iep_formatting_post_task.png"
}
EOF
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Safely signal application to quit
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2

kill_calligra_processes

echo "=== Export Complete ==="