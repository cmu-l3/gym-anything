#!/bin/bash
echo "=== Exporting Firefox PDF Archive Task Results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/WCAG21_Archive.pdf"

# Take final screenshot before altering application state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if output file was created and modified during the task
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# CRITICAL: Firefox only flushes preferences to disk (prefs.js) when closing.
# We must gracefully terminate it to inspect the print settings the agent applied.
echo "Flushing Firefox preferences to disk..."
pkill -15 -f firefox
sleep 3
# Force kill if it hangs
pkill -9 -f firefox 2>/dev/null || true

# Copy the flushed prefs.js to a temp location for the verifier
PREFS_PATH="/home/ga/.mozilla/firefox/default.profile/prefs.js"
if [ -f "$PREFS_PATH" ]; then
    cp "$PREFS_PATH" /tmp/firefox_prefs.js
    chmod 666 /tmp/firefox_prefs.js
    PREFS_EXISTS="true"
else
    PREFS_EXISTS="false"
fi

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "prefs_exists": $PREFS_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="