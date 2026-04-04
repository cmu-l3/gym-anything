#!/bin/bash
echo "=== Exporting SVM Gender Prediction Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

JASP_FILE="/home/ga/Documents/JASP/SVM_Gender_Analysis.jasp"
REPORT_FILE="/home/ga/Documents/JASP/svm_performance_report.txt"

# 1. Check JASP Project File
JASP_EXISTS="false"
JASP_CREATED_DURING="false"
JASP_SIZE="0"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c %Y "$JASP_FILE" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    
    # Read content (limit size)
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 1024)
fi

# 3. Check if JASP is running
APP_RUNNING="false"
if pgrep -f "org.jaspstats.JASP" > /dev/null || pgrep -f "JASP" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_created_during_task": $JASP_CREATED_DURING,
    "jasp_file_size": $JASP_SIZE,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_created_during_task": $REPORT_CREATED_DURING,
    "report_content": $(echo "$REPORT_CONTENT" | jq -R .),
    "app_was_running": $APP_RUNNING,
    "jasp_file_path": "$JASP_FILE"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy the JASP file itself to /tmp for the verifier to inspect content
if [ "$JASP_EXISTS" = "true" ]; then
    cp "$JASP_FILE" /tmp/analysis_result.jasp 2>/dev/null || true
    chmod 666 /tmp/analysis_result.jasp 2>/dev/null || true
fi

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="