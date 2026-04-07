#!/bin/bash
set -e

echo "=== Exporting configure_test_signal_channels result ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot captured."

# Check if OpenBCI GUI is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# Find the most recently created settings file
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
# Find files modified after task start
SETTINGS_FILE=$(find "$SETTINGS_DIR" -name "*.json" -newermt "@$TASK_START" 2>/dev/null | sort -r | head -n 1)

SETTINGS_FOUND="false"
SETTINGS_CONTENT="{}"
SETTINGS_FILENAME=""

if [ -n "$SETTINGS_FILE" ] && [ -f "$SETTINGS_FILE" ]; then
    SETTINGS_FOUND="true"
    SETTINGS_FILENAME=$(basename "$SETTINGS_FILE")
    # Read the content
    SETTINGS_CONTENT=$(cat "$SETTINGS_FILE")
    echo "Found new settings file: $SETTINGS_FILE"
else
    echo "No new settings file found."
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "settings_found": $SETTINGS_FOUND,
    "settings_filename": "$SETTINGS_FILENAME",
    "settings_content": $SETTINGS_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
# The verifier uses copy_from_env to retrieve this file
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="