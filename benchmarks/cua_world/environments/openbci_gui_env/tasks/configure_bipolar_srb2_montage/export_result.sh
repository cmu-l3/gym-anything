#!/bin/bash
echo "=== Exporting SRB2 Task Results ==="

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the specific screenshot requested exists
TARGET_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/srb2_config.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"
SCREENSHOT_SIZE="0"

if [ -f "$TARGET_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$TARGET_SCREENSHOT" 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c %Y "$TARGET_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Anti-gaming: File must be created AFTER task start
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        SCREENSHOT_VALID="true"
    fi
fi

# 2. Check if OpenBCI is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 3. Capture system state (Final Screenshot)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Generate JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_valid_time": $SCREENSHOT_VALID,
    "agent_screenshot_size": $SCREENSHOT_SIZE,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png",
    "agent_screenshot_path": "$TARGET_SCREENSHOT"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json