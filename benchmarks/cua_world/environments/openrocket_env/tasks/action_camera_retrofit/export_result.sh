#!/bin/bash
echo "=== Exporting action_camera_retrofit result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/camera_retrofit_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/camera_retrofitted.ork"
CSV_FILE="/home/ga/Documents/exports/camera_flight.csv"
REPORT_FILE="/home/ga/Documents/exports/retrofit_report.txt"

ork_exists="false"
csv_exists="false"
report_exists="false"

[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$CSV_FILE" ] && csv_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

csv_size=0
report_size=0
[ -f "$CSV_FILE" ] && csv_size=$(stat -c %s "$CSV_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"csv_exists\": $csv_exists,
  \"csv_size\": $csv_size,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/camera_retrofit_result.json

echo "=== Export complete ==="