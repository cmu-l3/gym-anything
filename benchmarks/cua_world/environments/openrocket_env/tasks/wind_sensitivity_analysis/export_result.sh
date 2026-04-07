#!/bin/bash
echo "=== Exporting wind_sensitivity_analysis result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/wind_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/wind_sensitivity.ork"
CSV_FILE="/home/ga/Documents/exports/wind_sensitivity.csv"
REPORT_FILE="/home/ga/Documents/exports/wind_report.txt"

ork_exists="false"
csv_exists="false"
report_exists="false"

[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$CSV_FILE" ] && csv_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

csv_size=0
csv_mtime=0
report_size=0
report_mtime=0

[ -f "$CSV_FILE" ] && { csv_size=$(stat -c %s "$CSV_FILE" 2>/dev/null); csv_mtime=$(stat -c %Y "$CSV_FILE" 2>/dev/null); }
[ -f "$REPORT_FILE" ] && { report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null); report_mtime=$(stat -c %Y "$REPORT_FILE" 2>/dev/null); }

# Extract task start timestamp
TASK_START_TS=$(grep "task_start_ts" /tmp/wind_gt.txt | cut -d'=' -f2)

write_result_json "{
  \"task_start_ts\": ${TASK_START_TS:-0},
  \"ork_exists\": $ork_exists,
  \"csv_exists\": $csv_exists,
  \"csv_size\": $csv_size,
  \"csv_mtime\": $csv_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size,
  \"report_mtime\": $report_mtime
}" /tmp/wind_result.json

echo "=== Export complete ==="