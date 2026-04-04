#!/bin/bash
echo "=== Exporting Fleiss' Kappa results ==="

# Source utilities (if available, otherwise define minimal logic)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 2. Check JASP Analysis File (.jasp)
JASP_FILE="/home/ga/Documents/JASP/diagnosis_reliability.jasp"
JASP_EXISTS="false"
JASP_CREATED_DURING_TASK="false"
JASP_SIZE=0

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Report File (.txt)
REPORT_FILE="/home/ga/Documents/JASP/reliability_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read content (limit to first 1KB to avoid huge payloads)
    REPORT_CONTENT=$(head -c 1024 "$REPORT_FILE")
fi

# 4. Check if JASP is still running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "jasp_file": {
        "exists": $JASP_EXISTS,
        "created_during_task": $JASP_CREATED_DURING_TASK,
        "size_bytes": $JASP_SIZE,
        "path": "$JASP_FILE"
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "content": $(echo "$REPORT_CONTENT" | jq -R .),
        "path": "$REPORT_FILE"
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="