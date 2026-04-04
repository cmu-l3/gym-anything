#!/bin/bash
echo "=== Exporting Cox Regression Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JASP_FILE="/home/ga/Documents/JASP/ChurnAnalysis.jasp"
REPORT_FILE="/home/ga/Documents/JASP/churn_risk_report.txt"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check JASP Project File
if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_NEW="true"
    else
        JASP_NEW="false"
    fi
else
    JASP_EXISTS="false"
    JASP_SIZE="0"
    JASP_NEW="false"
fi

# Check Report File
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | base64 -w 0)
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_NEW="true"
    else
        REPORT_NEW="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_CONTENT=""
    REPORT_NEW="false"
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_size": $JASP_SIZE,
    "jasp_file_created_during_task": $JASP_NEW,
    "jasp_file_path": "$JASP_FILE",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_NEW,
    "report_content_b64": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result to /tmp/task_result.json with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"