#!/bin/bash
set -e
echo "=== Exporting Add Spectrogram Widget results ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if OpenBCI GUI is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# Check for Screenshot existence
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Check if settings were modified (heuristic for activity)
SETTINGS_MODIFIED="false"
CURRENT_SETTINGS_STATE=$(ls -lR "/home/ga/Documents/OpenBCI_GUI/Settings" 2>/dev/null || echo "No settings")
INITIAL_SETTINGS_STATE=$(cat /tmp/initial_settings_state.txt 2>/dev/null || echo "No settings")

if [ "$CURRENT_SETTINGS_STATE" != "$INITIAL_SETTINGS_STATE" ]; then
    SETTINGS_MODIFIED="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "settings_modified": $SETTINGS_MODIFIED,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="