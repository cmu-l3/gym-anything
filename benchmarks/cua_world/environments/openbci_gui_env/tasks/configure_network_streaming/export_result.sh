#!/bin/bash
echo "=== Exporting Configure Network Streaming Result ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/networking_config.png"

# 1. Check if OpenBCI is running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 2. Check for Agent's Screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check for Network Port Activity (UDP 12345)
# This confirms the OSC stream was actually started on the correct port
PORT_OPEN="false"
if netstat -unlp 2>/dev/null | grep ":12345" > /dev/null; then
    PORT_OPEN="true"
fi

# 4. Take System Final Screenshot for VLM Verification
# We use a unique name to differentiate from the agent's screenshot
DISPLAY=:1 scrot /tmp/system_verification_screenshot.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_valid": $SCREENSHOT_CREATED_DURING_TASK,
    "agent_screenshot_size": $SCREENSHOT_SIZE,
    "osc_port_12345_open": $PORT_OPEN,
    "system_screenshot_path": "/tmp/system_verification_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json