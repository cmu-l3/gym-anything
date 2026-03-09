#!/bin/bash
echo "=== Exporting lmm_sleep_analysis results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JASP_FILE="/home/ga/Documents/JASP/Sleep_LMM.jasp"
REPORT_FILE="/home/ga/Documents/JASP/lmm_report.txt"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check JASP file
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_CREATED_DURING="false"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# 3. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read content safely, escape quotes for JSON
    REPORT_CONTENT=$(cat "$REPORT_FILE" | tr '\n' ' ' | sed 's/"/\\"/g')
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

# 4. Check if JASP is running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "jasp_file": {
        "exists": $JASP_EXISTS,
        "size": $JASP_SIZE,
        "created_during_task": $JASP_CREATED_DURING,
        "path": "$JASP_FILE"
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "content": "$REPORT_CONTENT",
        "created_during_task": $REPORT_CREATED_DURING,
        "path": "$REPORT_FILE"
    }
}
EOF

# 6. Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="