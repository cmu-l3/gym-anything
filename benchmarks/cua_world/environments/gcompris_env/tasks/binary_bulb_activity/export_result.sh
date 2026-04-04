#!/bin/bash
echo "=== Exporting Binary Bulbs Activity Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the agent saved the requested screenshot
AGENT_SCREENSHOT_PATH="/tmp/binary_bulb_final.png"
AGENT_SCREENSHOT_EXISTS="false"
AGENT_SCREENSHOT_SIZE="0"
AGENT_SCREENSHOT_TIME="0"

if [ -f "$AGENT_SCREENSHOT_PATH" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    AGENT_SCREENSHOT_SIZE=$(stat -c %s "$AGENT_SCREENSHOT_PATH" 2>/dev/null || echo "0")
    AGENT_SCREENSHOT_TIME=$(stat -c %Y "$AGENT_SCREENSHOT_PATH" 2>/dev/null || echo "0")
fi

# 2. Check if GCompris is still running
APP_RUNNING=$(pgrep -f "gcompris" > /dev/null && echo "true" || echo "false")

# 3. Take a system-level final screenshot (in case agent failed to take one)
# This allows us to verify the final state even if the file requirement wasn't met
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "agent_screenshot_size": $AGENT_SCREENSHOT_SIZE,
    "agent_screenshot_timestamp": $AGENT_SCREENSHOT_TIME,
    "app_was_running": $APP_RUNNING,
    "system_final_screenshot": "/tmp/task_final.png"
}
EOF

# Move result to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="