#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check expected screenshot
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/head_plot_layout.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_VALID="true"
    fi
    # Get size
    SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
else
    SCREENSHOT_SIZE="0"
fi

# Check if App is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final system screenshot (ground truth for VLM)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid_time": $SCREENSHOT_VALID,
    "screenshot_size": $SCREENSHOT_SIZE,
    "app_running": $APP_RUNNING,
    "final_system_screenshot": "/tmp/task_final.png",
    "agent_screenshot_path": "$EXPECTED_SCREENSHOT"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"