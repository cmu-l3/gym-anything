#!/bin/bash
echo "=== Exporting Monitor Electrode Impedance results ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if the agent created the requested screenshot
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/impedance_check.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$EXPECTED_SCREENSHOT")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if OpenBCI is still running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Capture system-level final screenshot (fallback/verification)
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "agent_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "agent_screenshot_path": "$EXPECTED_SCREENSHOT",
    "app_was_running": $APP_RUNNING,
    "system_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# If the agent screenshot exists, copy it to a temp location readable by copy_from_env
if [ "$SCREENSHOT_EXISTS" = "true" ]; then
    cp "$EXPECTED_SCREENSHOT" /tmp/agent_evidence.png
    chmod 666 /tmp/agent_evidence.png
fi

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="