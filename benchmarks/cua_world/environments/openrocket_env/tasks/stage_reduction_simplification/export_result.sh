#!/bin/bash
echo "=== Exporting stage_reduction_simplification result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

TARGET_ORK="/home/ga/Documents/rockets/two_stage_simplified.ork"
REPORT_FILE="/home/ga/Documents/exports/stage_reduction_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ork_exists="false"
report_exists="false"
ork_created_during_task="false"
report_created_during_task="false"
is_known_copy="false"

if [ -f "$TARGET_ORK" ]; then
    ork_exists="true"
    ORK_MTIME=$(stat -c %Y "$TARGET_ORK" 2>/dev/null || echo "0")
    if [ "$ORK_MTIME" -ge "$TASK_START" ]; then
        ork_created_during_task="true"
    fi
    # Use task_utils to check if it's just a copy of an existing example file
    is_known_copy=$(is_copy_of_known "$TARGET_ORK")
fi

report_size=0
if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        report_created_during_task="true"
    fi
fi

# Write structured result
write_result_json "{
  \"task_start\": $TASK_START,
  \"ork_exists\": $ork_exists,
  \"ork_created_during_task\": $ork_created_during_task,
  \"is_known_copy\": $is_known_copy,
  \"report_exists\": $report_exists,
  \"report_created_during_task\": $report_created_during_task,
  \"report_size\": $report_size
}" /tmp/task_result.json

echo "=== Export complete ==="