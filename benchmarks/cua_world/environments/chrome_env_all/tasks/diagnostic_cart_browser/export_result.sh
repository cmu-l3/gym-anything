#!/bin/bash
echo "=== Exporting Diagnostic Cart Browser Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Chrome is running
CHROME_RUNNING=$(pgrep -f "chrome" > /dev/null && echo "true" || echo "false")

# Gracefully close Chrome to force it to flush Preferences and Bookmarks to disk
echo "Closing Chrome to flush settings..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check modification time of preferences
PREFS_PATH="/home/ga/.config/google-chrome/Default/Preferences"
PREFS_MTIME=$(stat -c %Y "$PREFS_PATH" 2>/dev/null || echo "0")

SETTINGS_MODIFIED="false"
if [ "$PREFS_MTIME" -gt "$TASK_START" ]; then
    SETTINGS_MODIFIED="true"
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "chrome_was_running": $CHROME_RUNNING,
    "settings_modified_during_task": $SETTINGS_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="