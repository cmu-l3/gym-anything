#!/bin/bash
echo "=== Exporting crosswind_launch_compensation result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/crosswind_compensation.ork"
REPORT_FILE="/home/ga/Documents/exports/launch_compensation_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime="0"
report_size=0
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

task_start=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ork_modified_during_task="false"
if [ "$ork_mtime" -gt "$task_start" ]; then
    ork_modified_during_task="true"
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_modified_during_task\": $ork_modified_during_task,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/task_result.json

echo "=== Export complete ==="