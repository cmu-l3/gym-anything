#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if App is running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Capture Final Screenshot (CRITICAL for VLM verification)
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# 3. Check for specific settings files (optional secondary signal)
# OpenBCI v5 saves some widget settings in json files in Documents/OpenBCI_GUI/Settings
# We list them to see if any were modified recently
SETTINGS_MODIFIED="false"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
if [ -d "$SETTINGS_DIR" ]; then
    # Check for files modified after task start
    RECENT_FILES=$(find "$SETTINGS_DIR" -type f -newermt "@$TASK_START" 2>/dev/null)
    if [ -n "$RECENT_FILES" ]; then
        SETTINGS_MODIFIED="true"
        echo "Found modified settings files: $RECENT_FILES"
    fi
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "settings_modified": $SETTINGS_MODIFIED
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="