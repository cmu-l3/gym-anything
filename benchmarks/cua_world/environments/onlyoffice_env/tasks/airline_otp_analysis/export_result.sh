#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Airline OTP Analysis Result ==="

# Record end time
echo $(date +%s) > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || \
su - ga -c "DISPLAY=:1 import -window root /tmp/task_final.png" 2>/dev/null || true

# Try to save gracefully
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

# Force kill if still running
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi
sleep 1

REPORT_PATH="/home/ga/Documents/Spreadsheets/otp_analysis_report.xlsx"

if [ -f "$REPORT_PATH" ]; then
    echo "OTP analysis report saved: $REPORT_PATH"
    
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
else
    echo "OTP analysis report not found: $REPORT_PATH"
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

cat > /tmp/task_result.json << JSONEOF
{
  "task_name": "airline_otp_analysis",
  "task_start": $TASK_START,
  "task_end": $(cat /tmp/task_end_time.txt),
  "output_file_exists": $OUTPUT_EXISTS,
  "file_created_during_task": $FILE_CREATED_DURING_TASK,
  "output_file_size": $OUTPUT_SIZE
}
JSONEOF

echo "=== Export Complete ==="