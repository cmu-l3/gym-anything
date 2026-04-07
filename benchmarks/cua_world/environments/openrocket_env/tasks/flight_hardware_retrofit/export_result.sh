#!/bin/bash
# Export script for flight_hardware_retrofit task

echo "=== Exporting flight_hardware_retrofit result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/retrofit_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/flight_ready_retrofit.ork"
REPORT_FILE="/home/ga/Documents/exports/hardware_penalty_report.txt"
START_TS=$(cat /tmp/retrofit_gt.txt | grep task_start_ts | cut -d'=' -f2)

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime=0
report_size=0
created_during_task="false"

if [ -f "$ORK_FILE" ]; then
    ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null || echo "0")
    if [ "$ork_mtime" -gt "$START_TS" ]; then
        created_during_task="true"
    fi
fi

if [ -f "$REPORT_FILE" ]; then
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"created_during_task\": $created_during_task,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/retrofit_result.json

echo "=== Export complete ==="