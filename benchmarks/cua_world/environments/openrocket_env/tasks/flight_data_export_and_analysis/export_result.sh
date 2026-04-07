#!/bin/bash
echo "=== Exporting flight_data_export_and_analysis result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/flight_analysis_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/flight_analysis.ork"
REPORT_FILE="/home/ga/Documents/exports/flight_analysis_report.txt"
DATA_DIR="/home/ga/Documents/exports/flight_data"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

report_size=0
csv_count=0
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
[ -d "$DATA_DIR" ] && csv_count=$(ls "$DATA_DIR"/*.csv 2>/dev/null | wc -l)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size,
  \"csv_count\": $csv_count
}" /tmp/flight_analysis_result.json

echo "=== Export complete ==="
