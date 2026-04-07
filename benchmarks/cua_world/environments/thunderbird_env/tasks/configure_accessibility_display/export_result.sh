#!/bin/bash
set -euo pipefail
echo "=== Exporting Configure Accessibility Display task result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TB_PROFILE="/home/ga/.thunderbird/default-release"
PREFS_FILE="$TB_PROFILE/prefs.js"

# Copy prefs.js for verifier to safely read
if [ -f "$PREFS_FILE" ]; then
    cp "$PREFS_FILE" /tmp/task_prefs.js
    chmod 666 /tmp/task_prefs.js
    
    PREFS_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
    if [ "$PREFS_MTIME" -gt "$TASK_START" ]; then
        PREFS_MODIFIED="true"
    else
        PREFS_MODIFIED="false"
    fi
else
    echo "WARNING: prefs.js not found!"
    PREFS_MODIFIED="false"
    touch /tmp/task_prefs.js
    chmod 666 /tmp/task_prefs.js
fi

# Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Create JSON metadata result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prefs_modified_during_task": $PREFS_MODIFIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported."
echo "=== Export complete ==="