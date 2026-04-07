#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Expected screenshot path
EXPECTED_SCREENSHOT="/home/ga/Documents/OpenBCI_GUI/Screenshots/ganglion_dashboard.png"

# Check if the agent's screenshot exists
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Simple validity check (size > 1KB)
    if [ "$FILE_SIZE" -gt 1024 ]; then
        SCREENSHOT_VALID="true"
    fi
fi

# Check if App is running
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null || pgrep -f "java" > /dev/null; then
    APP_RUNNING="true"
fi

# Capture final system state screenshot (independent of agent's screenshot)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid": $SCREENSHOT_VALID,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "agent_screenshot_path": "$EXPECTED_SCREENSHOT",
    "system_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# If agent screenshot exists, copy it to /tmp for easier extraction by verifier if needed
if [ "$SCREENSHOT_EXISTS" = "true" ]; then
    cp "$EXPECTED_SCREENSHOT" /tmp/agent_screenshot.png
    chmod 666 /tmp/agent_screenshot.png
fi

echo "Results exported to /tmp/task_result.json"