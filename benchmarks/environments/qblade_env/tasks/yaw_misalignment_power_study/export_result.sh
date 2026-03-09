#!/bin/bash
echo "=== Exporting yaw_misalignment_power_study result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/Documents/projects/yaw_study.wpa"
REPORT_PATH="/home/ga/Documents/projects/yaw_power_report.csv"

# Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH" 2>/dev/null || echo "0")
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read first 10 lines of report for debug/backup
    REPORT_CONTENT=$(head -n 10 "$REPORT_PATH" | base64 -w 0)
fi

# Check if QBlade is running
APP_RUNNING=$(is_qblade_running)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="