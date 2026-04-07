#!/bin/bash
set -euo pipefail

echo "=== Exporting Zoning Ordinance Format Result ==="

export DISPLAY=:1

# Take final screenshot
echo "Capturing final state..."
scrot /tmp/task_final.png 2>/dev/null || \
    import -window root /tmp/task_final.png 2>/dev/null || true

DOC_PATH="/home/ga/Documents/tod_ordinance_draft.docx"
DOC_EXISTS="false"
DOC_SIZE="0"
FILE_CREATED_DURING_TASK="false"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

if [ -f "$DOC_PATH" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$DOC_PATH" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$DOC_PATH" 2>/dev/null || echo "0")
    
    if [ "$DOC_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy to tmp for verifier access
    cp "$DOC_PATH" /tmp/tod_ordinance_draft_result.docx
    chmod 666 /tmp/tod_ordinance_draft_result.docx
fi

APP_RUNNING=$(pgrep -f "wps" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "document_exists": $DOC_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "document_size_bytes": $DOC_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"

# Safely close WPS to clean up environment
echo "Closing WPS Writer..."
if [ "$APP_RUNNING" = "true" ]; then
    xdotool key --delay 200 alt+F4 2>/dev/null || true
    sleep 2
    xdotool key --delay 100 Tab 2>/dev/null || true
    sleep 0.5
    xdotool key --delay 100 Return 2>/dev/null || true
    sleep 1
    pkill -f "wps" 2>/dev/null || true
fi

echo "=== Export Complete ==="