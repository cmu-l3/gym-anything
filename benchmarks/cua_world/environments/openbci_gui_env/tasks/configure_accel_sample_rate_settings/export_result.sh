#!/bin/bash
echo "=== Exporting Configure Accel Sample Rate Results ==="

# Source utilities
source /home/ga/openbci_task_utils.sh || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/accel_config.png"

# 1. Capture the actual screen state at the end (System Verification)
# This is crucial in case the agent failed to save the file but did the UI work
take_screenshot /tmp/system_final_state.png

# 2. Check for the agent-generated screenshot
AGENT_SCREENSHOT_EXISTS="false"
AGENT_SCREENSHOT_SIZE="0"
AGENT_SCREENSHOT_VALID="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    AGENT_SCREENSHOT_EXISTS="true"
    AGENT_SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT")
    
    # Verify modification time
    FILE_TIME=$(stat -c %Y "$EXPECTED_SCREENSHOT")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        AGENT_SCREENSHOT_VALID="true"
    fi
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "agent_screenshot_exists": $AGENT_SCREENSHOT_EXISTS,
    "agent_screenshot_valid": $AGENT_SCREENSHOT_VALID,
    "agent_screenshot_path": "$EXPECTED_SCREENSHOT",
    "system_screenshot_path": "/tmp/system_final_state.png"
}
EOF

# Move JSON to accessible location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json