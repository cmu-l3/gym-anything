#!/bin/bash
set -e
echo "=== Exporting embed_meeting_iframe result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
HTML_FILE="/home/ga/Documents/meeting_portal.html"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check file status
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$HTML_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$HTML_FILE")
    FILE_MTIME=$(stat -c %Y "$HTML_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if Firefox is running
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move of result JSON
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

# Copy the HTML file to a temp location for the verifier to read (handling permissions)
if [ "$FILE_EXISTS" = "true" ]; then
    cp "$HTML_FILE" /tmp/submitted_portal.html
    chmod 644 /tmp/submitted_portal.html
fi

echo "=== Export complete ==="