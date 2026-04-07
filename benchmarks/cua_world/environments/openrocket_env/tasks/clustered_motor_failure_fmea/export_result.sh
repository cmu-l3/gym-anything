#!/bin/bash
echo "=== Exporting clustered_motor_failure_fmea result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/fmea_final.png 2>/dev/null || true

TARGET_ORK="/home/ga/Documents/rockets/clustered_fmea.ork"
REPORT_FILE="/home/ga/Documents/exports/fmea_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$TARGET_ORK" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime="0"
report_size="0"
[ -f "$TARGET_ORK" ] && ork_mtime=$(stat -c %Y "$TARGET_ORK" 2>/dev/null || echo "0")
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/fmea_result.json

echo "=== Export complete ==="