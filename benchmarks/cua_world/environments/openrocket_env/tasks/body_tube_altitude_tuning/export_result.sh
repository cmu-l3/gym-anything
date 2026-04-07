#!/bin/bash
echo "=== Exporting body_tube_altitude_tuning result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/task_final_state.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/altitude_tuning_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/altitude_tuning_report.txt"
START_TIME_FILE="/tmp/task_start_time.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime="0"
report_mtime="0"
report_size=0
task_start_ts="0"

[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_mtime=$(stat -c %Y "$REPORT_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
[ -f "$START_TIME_FILE" ] && task_start_ts=$(cat "$START_TIME_FILE" 2>/dev/null)

# Check if files were actually modified during the task
ork_modified_during_task="false"
report_created_during_task="false"

if [ "$ork_mtime" -gt "$task_start_ts" ]; then
    ork_modified_during_task="true"
fi

if [ "$report_mtime" -gt "$task_start_ts" ]; then
    report_created_during_task="true"
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_modified_during_task\": $ork_modified_during_task,
  \"report_exists\": $report_exists,
  \"report_created_during_task\": $report_created_during_task,
  \"report_size\": $report_size,
  \"task_start_ts\": $task_start_ts
}" /tmp/altitude_tuning_result.json

echo "=== Export complete ==="