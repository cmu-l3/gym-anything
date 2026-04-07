#!/bin/bash
echo "=== Exporting Configure Cyton Analog Mode results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the specific screenshot was created
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/analog_mode_config.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if App is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Capture Final State Screenshot (System verification screenshot)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_screenshot_exists": $SCREENSHOT_EXISTS,
    "evidence_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with relaxed permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="