#!/bin/bash
echo "=== Exporting internal_fin_can_structural_modeling result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

EXPECTED_ORK="/home/ga/Documents/rockets/fin_can_upgrade.ork"
EXPECTED_REPORT="/home/ga/Documents/exports/fin_can_report.txt"

ork_exists="false"
report_exists="false"
ork_created_during_task="false"
report_created_during_task="false"

if [ -f "$EXPECTED_ORK" ]; then
    ork_exists="true"
    ork_mtime=$(stat -c %Y "$EXPECTED_ORK" 2>/dev/null || echo "0")
    if [ "$ork_mtime" -gt "$TASK_START" ]; then
        ork_created_during_task="true"
    fi
fi

if [ -f "$EXPECTED_REPORT" ]; then
    report_exists="true"
    report_mtime=$(stat -c %Y "$EXPECTED_REPORT" 2>/dev/null || echo "0")
    if [ "$report_mtime" -gt "$TASK_START" ]; then
        report_created_during_task="true"
    fi
fi

APP_RUNNING=$(pgrep -f "OpenRocket.jar" > /dev/null && echo "true" || echo "false")

write_result_json "{
  \"task_start\": $TASK_START,
  \"task_end\": $TASK_END,
  \"app_was_running\": $APP_RUNNING,
  \"ork_exists\": $ork_exists,
  \"ork_created_during_task\": $ork_created_during_task,
  \"report_exists\": $report_exists,
  \"report_created_during_task\": $report_created_during_task
}" /tmp/task_result.json

echo "=== Export complete ==="