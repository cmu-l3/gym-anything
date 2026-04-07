#!/bin/bash
echo "=== Exporting parasitic_drag_aerodynamic_optimization result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/task_final.png 2>/dev/null || true

START_ORK="/home/ga/Documents/rockets/drag_heavy_rocket.ork"
OPTIMIZED_ORK="/home/ga/Documents/rockets/optimized_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/aerodynamic_report.txt"

start_ork_exists="false"
optimized_ork_exists="false"
report_exists="false"

[ -f "$START_ORK" ] && start_ork_exists="true"
[ -f "$OPTIMIZED_ORK" ] && optimized_ork_exists="true"
[ -f "$REPORT_FILE" ] && report_exists="true"

optimized_ork_mtime=0
report_mtime=0
report_size=0

[ -f "$OPTIMIZED_ORK" ] && optimized_ork_mtime=$(stat -c %Y "$OPTIMIZED_ORK" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_mtime=$(stat -c %Y "$REPORT_FILE" 2>/dev/null)
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

task_start=$(cat /tmp/aerodynamic_gt.txt | grep task_start_ts | cut -d'=' -f2)

write_result_json "{
  \"task_start_time\": $task_start,
  \"start_ork_exists\": $start_ork_exists,
  \"optimized_ork_exists\": $optimized_ork_exists,
  \"optimized_ork_mtime\": $optimized_ork_mtime,
  \"report_exists\": $report_exists,
  \"report_mtime\": $report_mtime,
  \"report_size\": $report_size
}" /tmp/aerodynamic_result.json

echo "=== Export complete ==="