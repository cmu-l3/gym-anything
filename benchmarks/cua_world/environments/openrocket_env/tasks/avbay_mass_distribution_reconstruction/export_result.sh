#!/bin/bash
echo "=== Exporting avbay_mass_distribution_reconstruction result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot for trajectory/manual verification
take_screenshot /tmp/avbay_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/detailed_avbay_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/avbay_report.txt"
GT_FILE="/tmp/avbay_gt.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime="0"
report_size=0
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

task_start_ts="0"
[ -f "$GT_FILE" ] && task_start_ts=$(grep "task_start_ts" "$GT_FILE" | cut -d'=' -f2)

write_result_json "{
  \"task_start_ts\": $task_start_ts,
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/avbay_result.json

echo "=== Export complete ==="