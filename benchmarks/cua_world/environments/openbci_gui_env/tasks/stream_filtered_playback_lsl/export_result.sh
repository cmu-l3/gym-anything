#!/bin/bash
echo "=== Exporting stream_filtered_playback_lsl result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/lsl_filtered_setup.png"

# Check if expected screenshot exists and was created during task
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"
SCREENSHOT_SIZE="0"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    F_TIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$F_TIME" -ge "$TASK_START" ]; then
        SCREENSHOT_VALID="true"
    fi
    SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
fi

# Capture final state of the screen (in case agent didn't take screenshot)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if OpenBCI is running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_valid_time": $SCREENSHOT_VALID,
    "agent_screenshot_size": $SCREENSHOT_SIZE,
    "agent_screenshot_path": "$EXPECTED_SCREENSHOT",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"