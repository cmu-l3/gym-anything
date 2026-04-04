#!/bin/bash
echo "=== Exporting RF Regression Result ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather File Statistics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JASP_FILE="/home/ga/Documents/JASP/rf_exam_analysis.jasp"
REPORT_FILE="/home/ga/Documents/JASP/rf_report.txt"

# Check JASP Project File
if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$JASP_FILE")
    JASP_MTIME=$(stat -c%Y "$JASP_FILE")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING_TASK="true"
    else
        JASP_CREATED_DURING_TASK="false"
    fi
else
    JASP_EXISTS="false"
    JASP_SIZE="0"
    JASP_CREATED_DURING_TASK="false"
fi

# Check Text Report File
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    else
        REPORT_CREATED_DURING_TASK="false"
    fi
    # Read content safely (max 1KB to prevent massive file reads)
    REPORT_CONTENT=$(head -c 1000 "$REPORT_FILE" | base64 -w 0)
else
    REPORT_EXISTS="false"
    REPORT_CREATED_DURING_TASK="false"
    REPORT_CONTENT=""
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "jasp_file": {
        "exists": $JASP_EXISTS,
        "size": $JASP_SIZE,
        "created_during_task": $JASP_CREATED_DURING_TASK,
        "path": "$JASP_FILE"
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "content_base64": "$REPORT_CONTENT",
        "path": "$REPORT_FILE"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Move to standard location with relaxed permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"