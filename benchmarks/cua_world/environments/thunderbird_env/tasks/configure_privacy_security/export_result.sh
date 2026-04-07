#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time and state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_prefs_mtime.txt 2>/dev/null || echo "0")

PROFILE_DIR="/home/ga/.thunderbird/default-release"
PREFS_FILE="${PROFILE_DIR}/prefs.js"

# Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# If Thunderbird is running, send a command to flush prefs to disk
if [ "$APP_RUNNING" = "true" ]; then
    echo "Thunderbird is running. Taking screenshot before copying prefs..."
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
    # Wait a moment to ensure latest prefs are flushed if they just closed a tab
    sleep 2
else
    echo "Thunderbird is not running."
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
fi

# Check if prefs.js was modified during the task
PREFS_MODIFIED="false"
CURRENT_MTIME="0"
if [ -f "$PREFS_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
        PREFS_MODIFIED="true"
    fi
    
    # Copy prefs file for the verifier to safely read
    cp "$PREFS_FILE" /tmp/exported_prefs.js
    chmod 666 /tmp/exported_prefs.js
else
    echo "WARNING: prefs.js not found at $PREFS_FILE"
    touch /tmp/exported_prefs.js
    chmod 666 /tmp/exported_prefs.js
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "prefs_modified_during_task": $PREFS_MODIFIED,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="