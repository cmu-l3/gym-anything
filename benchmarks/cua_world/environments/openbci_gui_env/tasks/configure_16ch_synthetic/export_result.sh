#!/bin/bash
echo "=== Exporting Configure 16-Channel Synthetic Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Expected screenshot path
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/16ch_synthetic_session.png"

# Check if the expected screenshot exists
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Verify it was created after task start
    if [ "$SCREENSHOT_MTIME" -ge "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    # Copy the agent's screenshot to temp for verification retrieval
    cp "$EXPECTED_SCREENSHOT" /tmp/agent_screenshot.png
    chmod 644 /tmp/agent_screenshot.png
fi

# Check if OpenBCI is still running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# Take a verification screenshot of the current state
# This is crucial for the VLM to verify the live state if the agent didn't take a screenshot,
# or to double-check the agent's screenshot.
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "agent_screenshot_size": $SCREENSHOT_SIZE,
    "app_was_running": $APP_RUNNING,
    "final_state_screenshot_path": "/tmp/task_final.png",
    "agent_screenshot_temp_path": "/tmp/agent_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="