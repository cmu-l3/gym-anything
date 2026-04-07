#!/bin/bash
echo "=== Exporting transonic_drag_optimization result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/transonic_final.png 2>/dev/null || true

BASELINE_ORK="/home/ga/Documents/rockets/transonic_rocket.ork"
OPTIMIZED_ORK="/home/ga/Documents/rockets/transonic_rocket_optimized.ork"
REPORT_FILE="/home/ga/Documents/exports/aerodynamic_report.txt"

ork_exists="false"
baseline_mtime=0
optimized_mtime=0
report_exists="false"
report_size=0

[ -f "$BASELINE_ORK" ] && baseline_mtime=$(stat -c %Y "$BASELINE_ORK" 2>/dev/null)
if [ -f "$OPTIMIZED_ORK" ]; then
    ork_exists="true"
    optimized_mtime=$(stat -c %Y "$OPTIMIZED_ORK" 2>/dev/null)
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
    report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)
fi

write_result_json "{
  \"optimized_ork_exists\": $ork_exists,
  \"baseline_ork_mtime\": $baseline_mtime,
  \"optimized_ork_mtime\": $optimized_mtime,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/transonic_result.json

echo "=== Export complete ==="