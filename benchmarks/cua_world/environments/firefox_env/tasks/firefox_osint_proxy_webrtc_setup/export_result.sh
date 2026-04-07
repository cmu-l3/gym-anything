#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Firefox is still running (it shouldn't be, according to task instructions)
APP_RUNNING="false"
if pgrep -u ga -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Define Firefox profile path
PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
PREFS_JS="$PROFILE_DIR/prefs.js"
USER_JS="$PROFILE_DIR/user.js"

# Copy configurations to /tmp so verifier can easily fetch them
rm -f /tmp/prefs.js /tmp/user.js 2>/dev/null
if [ -f "$PREFS_JS" ]; then
    cp "$PREFS_JS" /tmp/prefs.js
    PREFS_MTIME=$(stat -c %Y "$PREFS_JS" 2>/dev/null || echo "0")
else
    touch /tmp/prefs.js
    PREFS_MTIME="0"
fi

if [ -f "$USER_JS" ]; then
    cp "$USER_JS" /tmp/user.js
else
    touch /tmp/user.js
fi

# Determine if prefs.js was modified during the task
FILE_MODIFIED_DURING_TASK="false"
if [ "$PREFS_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED_DURING_TASK="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "prefs_mtime": $PREFS_MTIME,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json /tmp/prefs.js /tmp/user.js 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="