#!/bin/bash
echo "=== Exporting EMG Joystick Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
AGENT_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/emg_joystick_config.png"
SYSTEM_FINAL_SCREENSHOT="/tmp/task_final.png"

# Check if agent's screenshot exists and was created during the task
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$AGENT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$AGENT_SCREENSHOT" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$AGENT_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# Check if App is running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# Take system final screenshot (as backup/verification of state)
DISPLAY=:1 scrot "$SYSTEM_FINAL_SCREENSHOT" 2>/dev/null || true

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_valid": $SCREENSHOT_CREATED_DURING_TASK,
    "agent_screenshot_size": $SCREENSHOT_SIZE,
    "agent_screenshot_path": "$AGENT_SCREENSHOT",
    "system_screenshot_path": "$SYSTEM_FINAL_SCREENSHOT",
    "app_running": $APP_RUNNING
}
EOF

# Move result to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"