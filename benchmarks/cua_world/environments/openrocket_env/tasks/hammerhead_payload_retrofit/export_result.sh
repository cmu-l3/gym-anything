#!/bin/bash
echo "=== Exporting hammerhead_payload_retrofit result ==="

source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/hammerhead_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/hammerhead_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/hammerhead_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_mtime=0
report_size=0
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/hammerhead_result.json

echo "=== Export complete ==="