#!/bin/bash
echo "=== Exporting nose_cone_drag_optimization result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/optimized_nosecone_rocket.ork"
FALLBACK_ORK="/home/ga/Documents/rockets/drag_issue_rocket.ork"
REPORT_FILE="/home/ga/Documents/exports/nosecone_trade_study.txt"

ork_exists="false"
report_exists="false"

if [ -f "$ORK_FILE" ] || [ -f "$FALLBACK_ORK" ]; then
    ork_exists="true"
fi

if [ -f "$REPORT_FILE" ]; then
    report_exists="true"
fi

report_size=0
[ -f "$REPORT_FILE" ] && report_size=$(stat -c %s "$REPORT_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"report_exists\": $report_exists,
  \"report_size\": $report_size
}" /tmp/task_result.json

echo "=== Export complete ==="