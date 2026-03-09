#!/bin/bash
echo "=== Exporting Define Turbine Power Curve Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (critical for VLM)
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Check Project File
PROJECT_FILE="/home/ga/Documents/projects/NREL5MW_turbine_sim.wpa"
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_MODIFIED="false"

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE")
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_FILE")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_MODIFIED="true"
    fi
fi

# 4. Check Report File
REPORT_FILE="/home/ga/Documents/projects/power_curve_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MODIFIED="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
    # Read first 500 chars of report to avoid huge JSON
    REPORT_CONTENT=$(head -c 500 "$REPORT_FILE")
fi

# 5. Check if QBlade is still running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# 6. Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $CURRENT_TIME,
    "project_file": {
        "exists": $PROJECT_EXISTS,
        "size_bytes": $PROJECT_SIZE,
        "modified_during_task": $PROJECT_MODIFIED,
        "path": "$PROJECT_FILE"
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "content_snippet": $(jq -R -s '.' <<< "$REPORT_CONTENT"),
        "modified_during_task": $REPORT_MODIFIED
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
write_result_json "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"