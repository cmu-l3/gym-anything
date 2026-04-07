#!/bin/bash
set -e
echo "=== Exporting task results ==="

export DISPLAY="${DISPLAY:-:1}"

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

FILE_PATH="/home/ga/Documents/dives.ssrf"

# Check file states
CURRENT_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
CURRENT_MD5=$(md5sum "$FILE_PATH" 2>/dev/null | awk '{print $1}')
INITIAL_MD5=$(cat /tmp/ssrf_initial_md5.txt 2>/dev/null || echo "")

FILE_MODIFIED="false"
if [ "$CURRENT_MD5" != "$INITIAL_MD5" ] && [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Check if application is running
APP_RUNNING=$(pgrep -f "subsurface" > /dev/null && echo "true" || echo "false")

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="