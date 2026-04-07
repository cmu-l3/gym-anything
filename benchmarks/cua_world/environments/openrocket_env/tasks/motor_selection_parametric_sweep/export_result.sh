#!/bin/bash
echo "=== Exporting motor_selection_parametric_sweep result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/motor_sweep_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/motor_sweep.ork"
CSV_FILE="/home/ga/Documents/exports/motor_comparison.csv"
REPORT_FILE="/home/ga/Documents/exports/motor_selection_report.txt"

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
}" /tmp/motor_sweep_result.json

echo "=== Export complete ==="
