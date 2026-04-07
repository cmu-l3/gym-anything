#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Workforce Analytics Result ==="

TASK_START=$(cat /tmp/workforce_analytics_start_ts 2>/dev/null || echo "0")

# Capture final screenshot
su - ga -c "DISPLAY=:1 import -window root /tmp/workforce_analytics_final_screenshot.png" || true

# Save and cleanly close ONLYOFFICE if it's running
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

# Force kill if still lingering
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

sleep 1

REPORT_PATH="/home/ga/Documents/Spreadsheets/workforce_analytics.xlsx"

if [ -f "$REPORT_PATH" ]; then
    echo "Workforce analytics workbook saved: $REPORT_PATH"
    ls -lh "$REPORT_PATH"
    
    # Check if modified during task
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    echo "Workforce analytics workbook not found: $REPORT_PATH"
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || true
    FILE_MODIFIED="false"
fi

cat > /tmp/workforce_analytics_result.json << JSONEOF
{
  "task_name": "employee_attrition_workforce_analysis",
  "task_start_time": $TASK_START,
  "timestamp": $(date +%s),
  "output_file_exists": $([ -f "$REPORT_PATH" ] && echo "true" || echo "false"),
  "file_modified_during_task": $FILE_MODIFIED,
  "output_file_size": $(stat -c%s "$REPORT_PATH" 2>/dev/null || echo 0)
}
JSONEOF

echo "=== Export Complete ==="