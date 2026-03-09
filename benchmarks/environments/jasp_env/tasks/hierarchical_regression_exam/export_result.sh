#!/bin/bash
echo "=== Exporting Hierarchical Regression Results ==="

# 1. Capture Task End State
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Take Final Screenshot (Critical for VLM)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check JASP Project File (.jasp)
JASP_FILE="/home/ga/Documents/JASP/Hierarchical_Exam.jasp"
JASP_EXISTS="false"
JASP_VALID_TIME="false"
JASP_SIZE="0"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE")
    FILE_MTIME=$(stat -c %Y "$JASP_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JASP_VALID_TIME="true"
    fi
fi

# 4. Check Report File (.txt)
REPORT_FILE="/home/ga/Documents/JASP/hierarchical_report.txt"
REPORT_EXISTS="false"
REPORT_VALID_TIME="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_VALID_TIME="true"
    fi
    
    # Read content safely (limit size to prevent massive JSON)
    REPORT_CONTENT=$(head -c 2000 "$REPORT_FILE" | base64 -w 0)
fi

# 5. Check if JASP is running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Generate Result JSON
# We use a temp file and move it to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_created_during_task": $JASP_VALID_TIME,
    "jasp_file_size": $JASP_SIZE,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_created_during_task": $REPORT_VALID_TIME,
    "report_content_base64": "$REPORT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "jasp_file_path": "$JASP_FILE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="