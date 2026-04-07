#!/bin/bash
echo "=== Exporting configure_timeseries_scale results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the agent saved the requested screenshot
TARGET_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/timeseries_config.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"
SCREENSHOT_SIZE="0"

if [ -f "$TARGET_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    
    # Check creation time to ensure it was made DURING the task
    FILE_TIME=$(stat -c %Y "$TARGET_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        SCREENSHOT_VALID="true"
    fi
    
    SCREENSHOT_SIZE=$(stat -c %s "$TARGET_SCREENSHOT" 2>/dev/null || echo "0")
fi

# 2. Check if OpenBCI is still running (agent shouldn't close it)
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null || pgrep -f "java.*OpenBCI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Capture final system screenshot (ground truth for VLM)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_valid": $SCREENSHOT_VALID,
    "agent_screenshot_size": $SCREENSHOT_SIZE,
    "app_running": $APP_RUNNING,
    "final_system_screenshot": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"