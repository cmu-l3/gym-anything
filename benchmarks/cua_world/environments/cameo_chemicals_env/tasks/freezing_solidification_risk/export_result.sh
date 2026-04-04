#!/bin/bash
echo "=== Exporting Freezing Risk Assessment Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/freezing_risk_report.txt"

# 1. Check if output file exists and was created during task
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check modification time against task start
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
    
    # Read content for JSON export (safely encoded)
    # Python is safer for JSON escaping than bash/sed
    REPORT_CONTENT=$(python3 -c "import json, sys; print(json.dumps(open('$REPORT_PATH').read()))" 2>/dev/null || echo "\"\"")
else
    REPORT_EXISTS="false"
    CREATED_DURING_TASK="false"
    REPORT_MTIME="0"
    REPORT_SIZE="0"
    REPORT_CONTENT="\"\""
fi

# 2. Check if Firefox is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 4. Create JSON result
# We embed the content directly to simplify the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "report_content_json_string": $REPORT_CONTENT
}
EOF

# 5. Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="