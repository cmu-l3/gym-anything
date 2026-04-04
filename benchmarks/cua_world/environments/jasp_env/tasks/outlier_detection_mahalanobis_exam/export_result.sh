#!/bin/bash
echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_JASP="/home/ga/Documents/JASP/OutlierAnalysis.jasp"
OUTPUT_REPORT="/home/ga/Documents/JASP/outlier_report.txt"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check JASP Project File
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_MODIFIED="false"
if [ -f "$OUTPUT_JASP" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$OUTPUT_JASP")
    JASP_MTIME=$(stat -c%Y "$OUTPUT_JASP")
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_MODIFIED="true"
    fi
fi

# 3. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MODIFIED="false"
if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(head -n 1 "$OUTPUT_REPORT" | tr -d '\n\r')
    REPORT_MTIME=$(stat -c%Y "$OUTPUT_REPORT")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
fi

# 4. Check App State
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_size": $JASP_SIZE,
    "jasp_file_created_during_task": $JASP_MODIFIED,
    "report_file_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "report_file_created_during_task": $REPORT_MODIFIED,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "jasp_file_path": "$OUTPUT_JASP",
    "dataset_path": "/home/ga/Documents/JASP/ExamAnxiety.csv"
}
EOF

# 6. Safe Move to /tmp/task_result.json
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="