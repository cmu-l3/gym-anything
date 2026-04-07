#!/bin/bash
echo "=== Exporting tarc_altitude_time_calibration result ==="

source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/tarc_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/tarc_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/tarc_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime="0"
report_size="0"
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

# Verify against start time to prevent gaming with pre-existing files
start_time=$(cat /tmp/tarc_gt.txt | grep task_start_ts | cut -d'=' -f2)
[ -z "$start_time" ] && start_time=0

created_during_task="false"
if [ "$ork_mtime" -gt "$start_time" ]; then
    created_during_task="true"
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"created_during_task\": $created_during_task,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/tarc_result.json

echo "=== Export complete ==="