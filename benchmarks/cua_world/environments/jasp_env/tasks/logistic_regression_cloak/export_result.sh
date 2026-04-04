#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Define Paths
JASP_FILE="/home/ga/Documents/JASP/LogisticRegression_Cloak.jasp"
REPORT_FILE="/home/ga/Documents/JASP/logistic_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Analyze JASP File (Persistence Check)
JASP_EXISTS="false"
JASP_SIZE=0
JASP_VALID_ZIP="false"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$JASP_FILE")
    JASP_MTIME=$(stat -c%Y "$JASP_FILE")
    
    # Verify it was modified AFTER task start
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_NEWLY_CREATED="true"
    else
        JASP_NEWLY_CREATED="false"
    fi

    # Basic validity check: JASP files are ZIPs
    if unzip -t "$JASP_FILE" >/dev/null 2>&1; then
        JASP_VALID_ZIP="true"
    fi
else
    JASP_NEWLY_CREATED="false"
fi

# 4. Analyze Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read content, limit to 1KB to prevent massive logs
    REPORT_CONTENT=$(head -c 1000 "$REPORT_FILE" | base64 -w 0)
fi

# 5. Check App State
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file": {
        "exists": $JASP_EXISTS,
        "size": $JASP_SIZE,
        "is_valid_zip": $JASP_VALID_ZIP,
        "created_during_task": $JASP_NEWLY_CREATED
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "content_base64": "$REPORT_CONTENT"
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Safe Move to Output
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"