#!/bin/bash
echo "=== Exporting Monitor Mu Rhythm results ==="

# 1. basic info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Check for agent's screenshot
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/mu_rhythm_config.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$EXPECTED_SCREENSHOT")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if App is running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Capture Final State Screenshot (System level)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "final_system_screenshot": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="