#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Academic Journal Typesetting Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOC_PATH="/home/ga/Documents/crispr_brassica_manuscript.odt"

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Check if Calligra is running
APP_RUNNING="false"
if pgrep -f "calligrawords" > /dev/null; then
    APP_RUNNING="true"
fi

# Check file modification
FILE_MODIFIED="false"
FILE_SIZE="0"
if [ -f "$DOC_PATH" ]; then
    FILE_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$DOC_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Save export metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_was_running": $APP_RUNNING,
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "task_start": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Safely kill the application so the container can shutdown
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 2
kill_calligra_processes

echo "=== Export Complete ==="