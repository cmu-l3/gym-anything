#!/bin/bash
echo "=== Exporting Storm Thrust Analysis results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_PATH="/home/ga/Documents/projects/storm_analysis.wpa"
REPORT_PATH="/home/ga/Documents/projects/storm_report.txt"

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Report File and Content
REPORT_EXISTS="false"
THRUST_0="0"
THRUST_90="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Extract numbers using grep/sed. Assuming format "Thrust at X deg: 12345 N"
    # We look for lines containing "0 deg" or "90 deg" and extract the first number found
    
    # Extract Thrust at 0 deg
    LINE_0=$(grep -i "0 deg" "$REPORT_PATH" | head -1)
    # Extract number (integer or float)
    THRUST_0=$(echo "$LINE_0" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1 || echo "0")
    
    # Extract Thrust at 90 deg
    LINE_90=$(grep -i "90 deg" "$REPORT_PATH" | head -1)
    THRUST_90=$(echo "$LINE_90" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1 || echo "0")
fi

# 3. Check if QBlade is running
APP_RUNNING=$(is_qblade_running)

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "thrust_0_reported": $THRUST_0,
    "thrust_90_reported": $THRUST_90,
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="