#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PREFS_TIME=$(cat /tmp/initial_prefs_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Give Thunderbird a moment to flush preferences to disk
sleep 2

# Force flush if needed (closing main window safely triggers prefs save)
# We won't kill it aggressively to avoid corrupting prefs.js
su - ga -c "DISPLAY=:1 wmctrl -c 'Settings'" 2>/dev/null || true
sleep 1

# Locate the active prefs.js
PREFS_FILE=$(find /home/ga/.thunderbird -name "prefs.js" | head -n 1)
PREFS_MTIME=0
PREFS_COPIED="false"

if [ -n "$PREFS_FILE" ] && [ -f "$PREFS_FILE" ]; then
    PREFS_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
    
    # Copy to a predictable, readable location for the verifier
    cp "$PREFS_FILE" /tmp/task_prefs.js 2>/dev/null || sudo cp "$PREFS_FILE" /tmp/task_prefs.js
    chmod 666 /tmp/task_prefs.js 2>/dev/null || sudo chmod 666 /tmp/task_prefs.js 2>/dev/null || true
    PREFS_COPIED="true"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_prefs_mtime": $INITIAL_PREFS_TIME,
    "final_prefs_mtime": $PREFS_MTIME,
    "prefs_copied": $PREFS_COPIED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="