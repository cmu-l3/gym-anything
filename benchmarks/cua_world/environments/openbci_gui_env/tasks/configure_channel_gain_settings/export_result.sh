#!/bin/bash
echo "=== Exporting Configure Channel Gain Settings results ==="

# Source utilities
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    function take_screenshot() { scrot "$1" 2>/dev/null || true; }
fi

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
REPORT_PATH="/home/ga/Documents/OpenBCI_GUI/gain_report.txt"
SCREENSHOT_PATH="/home/ga/Documents/OpenBCI_GUI/Screenshots/gain_config.png"

# Check if application is running
APP_RUNNING=$(pgrep -f "OpenBCI_GUI" > /dev/null && echo "true" || echo "false")

# 1. Verify Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content for verification (limit size)
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000)
fi

# 2. Verify Agent Screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Capture Final State Screenshot (for VLM verification)
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "report_file": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "content": $(echo "$REPORT_CONTENT" | jq -R .)
    },
    "agent_screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
        "path": "$SCREENSHOT_PATH"
    },
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="