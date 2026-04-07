#!/bin/bash
echo "=== Exporting fleet_launch_day_review result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/fleet_review_final.png 2>/dev/null || true

LAUNCH_DAY_DIR="/home/ga/Documents/rockets/launch_day"
CSV_FILE="/home/ga/Documents/exports/fleet_summary.csv"
REPORT_FILE="/home/ga/Documents/exports/launch_day_briefing.txt"

csv_exists="false"
report_exists="false"
[ -f "$CSV_FILE" ] && csv_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

csv_size=0
report_size=0
[ -f "$CSV_FILE" ] && csv_size=$(stat -c %s "$CSV_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"csv_exists\": $csv_exists,
  \"csv_size\": $csv_size,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/fleet_review_result.json

echo "=== Export complete ==="