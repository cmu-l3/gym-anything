#!/bin/bash
echo "=== Exporting internal_cg_repositioning result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/exports/cg_optimized.ork"
REPORT_FILE="/home/ga/Documents/exports/cg_optimization_report.txt"

ork_exists="false"
report_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

ork_size=0
report_size=0
[ -f "$ORK_FILE" ] && ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

# Check if application was running
app_running="false"
pgrep -f "OpenRocket.jar" > /dev/null && app_running="true"

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size,
  \"app_running\": $app_running
}" /tmp/task_result.json

echo "=== Export complete ==="