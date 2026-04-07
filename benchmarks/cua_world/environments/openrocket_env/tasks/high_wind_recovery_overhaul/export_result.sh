#!/bin/bash
echo "=== Exporting high_wind_recovery_overhaul result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/high_wind_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/simple_model_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/wind_mitigation_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

report_size=0
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/high_wind_result.json

echo "=== Export complete ==="