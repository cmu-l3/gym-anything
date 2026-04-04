#!/bin/bash
echo "=== Exporting Traffic Puzzle task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check for the agent-created screenshot
SCREENSHOT_PATH="/tmp/traffic_completed.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID_TIME="false"
SCREENSHOT_SIZE="0"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_VALID_TIME="true"
    fi
fi

# 2. Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Check for GCompris configuration/data changes (evidence of activity)
# GCompris Qt stores data in ~/.local/share/GCompris/
DATA_MODIFIED="false"
DATA_DIR="/home/ga/.local/share/GCompris"
if [ -d "$DATA_DIR" ]; then
    # Find any file modified after start time
    RECENT_FILES=$(find "$DATA_DIR" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
    if [ "$RECENT_FILES" -gt 0 ]; then
        DATA_MODIFIED="true"
    fi
fi

# 4. Take final screenshot of the desktop state
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid_time": $SCREENSHOT_VALID_TIME,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "app_running": $APP_RUNNING,
    "data_modified": $DATA_MODIFIED
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="