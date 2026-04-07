#!/bin/bash
echo "=== Exporting Ganglion Montage Task Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot for VLM verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if OpenBCI is running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# Check for settings files (OpenBCI saves settings to JSON, though often only on exit/save)
# We look for evidence of Ganglion or Channel settings modifications
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
MODIFIED_FILES=$(find "$SETTINGS_DIR" -name "*.json" -newermt "@$TASK_START" 2>/dev/null | wc -l)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "settings_files_modified": $MODIFIED_FILES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="