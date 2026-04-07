#!/bin/bash
echo "=== Exporting Ellipsoid Volume Estimation task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

REPORT_PATH="/home/ga/DICOM/exports/volume_report.json"
SCREENSHOT_PATH="/home/ga/DICOM/exports/volume_measurements.png"

REPORT_EXISTS="false"
SCREENSHOT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
AGENT_JSON_CONTENT="{}"

# Verify Report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Try to parse the JSON content to embed it safely
    if python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$REPORT_PATH" 2>/dev/null; then
        AGENT_JSON_CONTENT=$(cat "$REPORT_PATH")
    else
        AGENT_JSON_CONTENT="{\"error\": \"Invalid JSON format in agent output\"}"
    fi
fi

# Verify Agent Screenshot
if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
fi

APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "app_was_running": $APP_RUNNING,
    "agent_json": $AGENT_JSON_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="