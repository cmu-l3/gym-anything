#!/bin/bash
echo "=== Exporting Piano Melody results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Check for the agent-generated screenshot
SCREENSHOT_PATH="/tmp/piano_result.png"
SCREENSHOT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
SCREENSHOT_SIZE="0"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    # Fallback: if agent didn't save to specific path but we want to capture state
    echo "Agent did not save to /tmp/piano_result.png, capturing current state..."
    take_screenshot "$SCREENSHOT_PATH"
    if [ -f "$SCREENSHOT_PATH" ]; then
        # We don't credit "FILE_CREATED_DURING_TASK" if we had to take it ourselves
        # but we allow it for VLM verification
        SCREENSHOT_EXISTS="true"
    fi
fi

# Take a framework-level final screenshot just in case
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_size": $SCREENSHOT_SIZE,
    "screenshot_path": "$SCREENSHOT_PATH"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="