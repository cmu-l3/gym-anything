#!/bin/bash
echo "=== Exporting supersonic_fin_flutter_mitigation result ==="

source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/flutter_task_final.png 2>/dev/null || true

UPGRADE_ORK="/home/ga/Documents/rockets/supersonic_upgrade.ork"
REPORT_FILE="/home/ga/Documents/exports/flutter_report.txt"
START_TIME_FILE="/tmp/flutter_task_gt.txt"

task_start_ts=$(grep "task_start_ts" "$START_TIME_FILE" | cut -d'=' -f2 2>/dev/null || echo "0")

ork_exists="false"
ork_mtime=0
ork_created_during_task="false"
report_exists="false"
report_size=0

if [ -f "$UPGRADE_ORK" ]; then
    ork_exists="true"
    ork_mtime=$(stat -c %Y "$UPGRADE_ORK" 2>/dev/null)
    if [ "$ork_mtime" -gt "$task_start_ts" ]; then
        ork_created_during_task="true"
    fi
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
fi

write_result_json "{
  \"task_start_ts\": $task_start_ts,
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"ork_created_during_task\": $ork_created_during_task,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/flutter_result.json

echo "=== Export complete ==="