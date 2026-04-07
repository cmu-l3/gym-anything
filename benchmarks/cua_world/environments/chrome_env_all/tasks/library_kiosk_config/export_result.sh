#!/bin/bash
echo "=== Exporting library_kiosk_config results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE killing chrome
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if Chrome was running
APP_RUNNING=$(pgrep -f "chrome" > /dev/null && echo "true" || echo "false")

# Gracefully close Chrome to force it to flush Preferences and Local State to disk
echo "Closing Chrome to flush settings to disk..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 4

# Check file modification times for anti-gaming
PREFS_PATH="/home/ga/.config/google-chrome-cdp/Default/Preferences"
LOCAL_STATE_PATH="/home/ga/.config/google-chrome-cdp/Local State"

PREFS_MODIFIED="false"
LOCAL_STATE_MODIFIED="false"

if [ -f "$PREFS_PATH" ]; then
    PREFS_MTIME=$(stat -c %Y "$PREFS_PATH" 2>/dev/null || echo "0")
    if [ "$PREFS_MTIME" -gt "$TASK_START" ]; then
        PREFS_MODIFIED="true"
    fi
fi

if [ -f "$LOCAL_STATE_PATH" ]; then
    LS_MTIME=$(stat -c %Y "$LOCAL_STATE_PATH" 2>/dev/null || echo "0")
    if [ "$LS_MTIME" -gt "$TASK_START" ]; then
        LOCAL_STATE_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "prefs_modified_during_task": $PREFS_MODIFIED,
    "local_state_modified_during_task": $LOCAL_STATE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="