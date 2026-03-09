#!/bin/bash
echo "=== Exporting Water Cycle Restoration Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
TEXT_FILE="/home/ga/Documents/water_cycle_status.txt"
SCREENSHOT_FILE="/home/ga/Documents/active_cycle.png"

# Check Text File
TEXT_FILE_EXISTS="false"
TEXT_CONTENT_MATCH="false"
TEXT_FILE_SIZE="0"
if [ -f "$TEXT_FILE" ]; then
    TEXT_FILE_EXISTS="true"
    TEXT_FILE_SIZE=$(stat -c %s "$TEXT_FILE" 2>/dev/null || echo "0")
    
    # Check creation time to ensure it was made during the task
    FILE_MTIME=$(stat -c %Y "$TEXT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi

    # Check content
    if grep -Fq "Simulation verified: Water cycle is active." "$TEXT_FILE"; then
        TEXT_CONTENT_MATCH="true"
    fi
else
    FILE_CREATED_DURING_TASK="false"
fi

# Check Screenshot File
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
if [ -f "$SCREENSHOT_FILE" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_FILE" 2>/dev/null || echo "0")
fi

# Check if GCompris is still running
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# Capture final state screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "text_file_exists": $TEXT_FILE_EXISTS,
    "text_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "text_content_match": $TEXT_CONTENT_MATCH,
    "screenshot_file_exists": $SCREENSHOT_EXISTS,
    "screenshot_file_size": $SCREENSHOT_SIZE,
    "app_was_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="